;;; gen_statem variant of auction-server (phase 6, not needed for parity).
;;;
;;; Same call protocol as auction-server, plus two things a gen_server cannot
;;; do as naturally:
;;;
;;;   - a state_timeout armed at the auction's expiry, so an auction ends on
;;;     its own and publishes AuctionEnded rather than waiting for a reader to
;;;     notice it has lapsed;
;;;   - hibernation once ended, so a long-lived node stops paying for auctions
;;;     that will never change again.
;;;
;;; Select it with {auction_module, 'auction-statem'} in the application
;;; environment.
;;;
;;; The timer is armed off the real clock while domain decisions still go
;;; through clock:now/0. Pinning the clock therefore does not pin the timer,
;;; which is why parity testing uses the gen_server instead.
(defmodule auction-statem
  (behaviour gen_statem)
  ;; gen_statem implementation
  (export
   (start_link 3))
  ;; callback implementation
  (export
   (init 1)
   (callback_mode 0)
   (handle_event 4)
   (terminate 3)
   (code_change 4)))

(include-lib "auctions/include/auctions.lfe")

(defun RETRY () 1000)

(defun start_link (id a at)
  (gen_statem:start_link `#(via auction-registry ,id)
                         (MODULE)
                         (list id a at)
                         '()))

(defun callback_mode () '(handle_event_function state_enter))

;;; -----------------------
;;; start and recovery
;;; -----------------------

(defun init
  (((list id a at))
   `#(ok booting #M(id ,id auction ,a at ,at) (#(next_event internal boot)))))

;; Same split as auction-server: the synced write runs in an internal
;; `boot' event, which is queued ahead of any call.
(defun boot (id a at)
  (event-store:sync)
  (case (event-store:events-for id)
    (() (fresh id a at))
    (events (recover id events))))

(defun fresh (id a at)
  (case (append-added at a)
    ('ok
     (auction-registry:set-auction id a)
     (ready id a (auction:empty-state a) 'false))
    (`#(error ,_reason)
     `#(stop normal))))

(defun append-added (at a)
  (try
    (event-store:append `#(auction-added ,at ,a))
    (catch ((tuple 'exit reason _) `#(error ,reason)))))

(defun recover (id events)
  (let ((repository (commands:fold-events events)))
    (case (maps:find id repository)
      (`#(ok #(,a ,state))
       (auction-registry:set-auction id a)
       (ready id a state (published? events)))
      ('error
       (logger:error "auction ~p has a corrupt log" (list id))
       `#(stop normal)))))

;; An auction that lapsed while the node was down starts up ended, and
;; publishes AuctionEnded on entry unless the log already has it.
(defun ready (id a state published)
  (let* ((advanced (auction-state:inc (clock:now) state))
         (data (map 'id id 'auction a 'state advanced 'published published)))
    (if (auction-state:has-ended advanced)
      `#(next_state ended ,data)
      `#(next_state active ,data))))

(defun published? (events)
  (lists:any (lambda (e) (=:= (element 1 e) 'auction-ended)) events))

;;; -----------------------
;;; event handling
;;; -----------------------

(defun handle_event
  (('enter _old 'booting _data)
   'keep_state_and_data)

  (('internal 'boot 'booting (map 'id id 'auction a 'at at))
   (boot id a at))

  ;; Arm the expiry timer whenever we (re)enter the active state.
  (('enter _old 'active data)
   `#(keep_state_and_data (,(expiry-timeout data))))

  ;; Nothing will change again, so give the memory back. If the end has not
  ;; been recorded yet, do that first.
  (('enter _old 'ended data)
   (if (maps:get 'published data)
     '#(keep_state_and_data (hibernate))
     '#(keep_state_and_data (#(state_timeout 0 publish)))))

  ;; Expiry reached. A bid may have pushed the expiry out while the timer was
  ;; running, in which case the auction is still live and we simply re-arm.
  (('state_timeout 'expired 'active data)
   (let* ((advanced (auction-state:inc (clock:now) (maps:get 'state data)))
          (next (maps:put 'state advanced data)))
     (if (auction-state:has-ended advanced)
       `#(next_state ended ,next)
       `#(keep_state ,next (,(expiry-timeout next))))))

  (('state_timeout 'publish 'ended data)
   (case (event-store:append `#(auction-ended ,(clock:now) ,(maps:get 'id data)))
     ('ok
      `#(keep_state ,(maps:put 'published 'true data) (hibernate)))
     (`#(error ,_reason)
      ;; The store is unavailable; the auction is still ended, so keep trying
      ;; rather than losing the record of it.
      `#(keep_state_and_data (#(state_timeout ,(RETRY) publish))))))

  ((`#(call ,from) `#(place-bid ,at ,b) fsm data)
   (place-bid from at b fsm data))

  ((`#(call ,from) `#(get ,now) fsm data)
   (answer from
           `#(ok #(,(maps:get 'auction data)
                   ,(auction-state:inc now (maps:get 'state data))))
           fsm))

  ;; Answered only once `boot' has completed, which is what the facade's
  ;; create waits for.
  ((`#(call ,from) 'ready fsm _data)
   (answer from 'ok fsm))

  ((`#(call ,from) 'stop _fsm data)
   `#(stop_and_reply shutdown (#(reply ,from ok)) ,data))

  ((`#(call ,from) _msg fsm _data)
   (answer from '#(error "Unknown command.") fsm))

  ((_type _content _fsm _data)
   'keep_state_and_data))

;; Identical to the gen_server's rule: the bid is acknowledged only once
;; BidAccepted is on disk, and neither a domain nor a store failure advances
;; the stored state.
(defun place-bid (from at b fsm data)
  (let ((a (maps:get 'auction data))
        (s (maps:get 'state data)))
    (case (auction:validate-bid b a)
      (`#(error ,e)
       (answer from `#(error ,e) fsm))
      ('ok
       (let ((`#(,s2 ,result) (auction-state:add-bid b s)))
         (case result
           ('ok
            (case (event-store:append `#(bid-accepted ,at ,b))
              ('ok (accepted from at b fsm (maps:put 'state s2 data)))
              (`#(error ,_)
               (answer from '#(error event-store-unavailable) fsm))))
           (`#(error ,_e)
            (answer from result fsm))))))))

;; A bid can extend the expiry, so the timer is replaced on every acceptance.
(defun accepted (from at b fsm data)
  (let ((reply `#(reply ,from #(ok #(bid-accepted ,at ,b)))))
    (if (=:= fsm 'active)
      `#(keep_state ,data (,reply ,(expiry-timeout data)))
      `#(keep_state ,data ,(cons reply (idle fsm))))))

;;; -----------------
;;; private functions
;;; -----------------

;; Answering a call wakes an ended auction up, so put it straight back to
;; sleep; otherwise the first read undoes the hibernation for good.
(defun answer (from reply fsm)
  `#(keep_state_and_data ,(cons `#(reply ,from ,reply) (idle fsm))))

(defun idle
  (('ended) '(hibernate))
  ((_) '()))

(defun expiry-timeout (data)
  `#(state_timeout ,(delay (maps:get 'state data)) expired))

(defun delay (state)
  (max 0 (- (auction-state:expiry state) (clock:now))))

(defun terminate (_reason _fsm _data) 'ok)

(defun code_change (_old fsm data _extra) `#(ok ,fsm ,data))
