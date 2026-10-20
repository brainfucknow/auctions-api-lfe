;;; One gen_server per auction. This process is the port's replacement for the
;;; single TVar the Haskell app serializes every write through: PlaceBid
;;; touches exactly one auction, so one sequential process per auction is
;;; enough to make bidding safe without a global lock.
;;;
;;; The process stays dumb - it holds a tagged tuple and delegates every
;;; decision to the pure state machines.
(defmodule auction-server
  (behaviour gen_server)
  ;; gen_server implementation
  (export
   (start_link 3))
  ;; callback implementation
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

;;; -----------------------
;;; callback implementation
;;; -----------------------

;; init only records its arguments. start_child blocks the supervisor until
;; init returns, so the synced write happens in handle_continue instead. A
;; continue runs before the first call, so no call is answered until the
;; auction is on disk or recovered.
(defun init
  (((list id a at))
   `#(ok #M(id ,id auction ,a at ,at) #(continue boot))))

;; Recovery and first start are the same code path. If the log already has
;; events for this id we are being restarted, so fold them and write nothing;
;; otherwise this is a fresh create and AuctionAdded must reach disk before
;; `ready' is answered. On failure the process stops normally: the
;; supervisor does not restart it, and the facade's call exits instead.
(defun handle_continue
  (('boot (= (map 'id id 'auction a 'at at) data))
   ;; Barrier first: if this process is replacing one that timed out mid
   ;; append, that write may still be queued in the store. `sync' returns only
   ;; once the store has worked past it, so the index read below reflects what
   ;; actually reached disk rather than a snapshot taken too early.
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

;; An append that times out exits; that used to fail init, and now fails the
;; create the same way.
(defun append-added (at a)
  (try
    (event-store:append `#(auction-added ,at ,a))
    (catch ((tuple 'exit reason _) `#(error ,reason)))))

(defun handle_call
  ;; A bid is acknowledged only once BidAccepted is on disk. On a store
  ;; failure the auction keeps its old state: an I/O failure is not a domain
  ;; decision, so the client is told to retry rather than shown a changed
  ;; auction. On a domain failure the state is likewise left alone, matching
  ;; Haskell's `handle', which discards the incremented repository.
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
