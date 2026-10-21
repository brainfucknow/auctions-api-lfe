;;; Serializes writes per auction; domain rules live in the pure state machines.
(defmodule auction-server
  (behaviour gen_server)
  (export
   (start_link 3))
  (export
   (init 1)
   (handle_continue 2)
   (handle_call 3)
   (handle_cast 2)
   (handle_info 2)
   (terminate 2)
   (code_change 3)))

(include-lib "auctions/include/auctions.lfe")

(defun start_link (id a at)
  (gen_server:start_link `#(via auction-registry ,id)
                         (MODULE)
                         (list id a at)
                         '()))

;; Defer disk I/O to handle_continue to avoid blocking the supervisor.
;; Recovery or creation completes before the first call is handled.
(defun init
  (((list id a at))
   `#(ok #M(id ,id auction ,a at ,at) #(continue boot))))

;; Replay existing events or persist AuctionAdded for a new auction.
;; On failure, stop normally to prevent a supervisor restart loop.
(defun handle_continue
  (('boot (= (map 'id id 'auction a 'at at) data))
   ;; Settle any append left queued by the previous process before reading the index.
   (event-store:sync)
   (case (event-store:events-for id)
     (()
      (case (append-added at a)
        ('ok
         (auction-registry:set-auction id a)
         `#(noreply ,(map 'auction a 'state (auction:empty-state a))))
        (`#(error ,_reason)
         (give-up id data))))
     (events
      (let ((repository (commands:fold-events events)))
        (case (maps:find id repository)
          (`#(ok #(,recovered ,state))
           (auction-registry:set-auction id recovered)
           `#(noreply ,(map 'auction recovered 'state state)))
          ('error
           (logger:error "auction ~p has a corrupt log" (list id))
           (give-up id data))))))))

;; Free the id before stopping; see auction-registry:release.
(defun give-up (id data)
  (auction-registry:release id)
  `#(stop normal ,data))

;; Convert append exits into create errors.
(defun append-added (at a)
  (try
    (event-store:append `#(auction-added ,at ,a))
    (catch ((tuple 'exit reason _) `#(error ,reason)))))

(defun handle_call
  ;; Persist BidAccepted before acknowledging. Keep the old state on store
  ;; or domain errors, matching Haskell's `handle'.
  ((`#(place-bid ,at ,b) _from (= (map 'auction a 'state s) data))
   (case (auction:validate-bid b a)
     (`#(error ,e)
      `#(reply #(error ,e) ,data))
     ('ok
      (let ((`#(,s2 ,result) (auction-state:add-bid b s)))
        (case result
          ('ok
           (case (event-store:append `#(bid-accepted ,at ,b))
             ('ok
              `#(reply #(ok #(bid-accepted ,at ,b)) ,(maps:put 'state s2 data)))
             (`#(error ,_reason)
              `#(reply #(error event-store-unavailable) ,data))))
          (`#(error ,_e)
           `#(reply ,result ,data)))))))
  ;; Reads increment lazily and do not store the result, as in Haskell.
  ((`#(get ,now) _from (= (map 'auction a 'state s) data))
   `#(reply #(ok #(,a ,(auction-state:inc now s))) ,data))
  ;; Answered only once `boot' has completed, which is what the facade's
  ;; create waits for.
  (('ready _from data)
   `#(reply ok ,data))
  (('stop _from data)
   `#(stop shutdown ok ,data))
  ((_msg _from data)
   `#(reply #(error "Unknown command.") ,data)))

(defun handle_cast (_msg data) `#(noreply ,data))

(defun handle_info (_msg data) `#(noreply ,data))

(defun terminate (_reason _data) 'ok)

(defun code_change (_old data _extra) `#(ok ,data))
