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

;; Recovery and first start are the same code path. If the log already has
;; events for this id we are being restarted, so fold them and write nothing;
;; otherwise this is a fresh create and AuctionAdded must reach disk before
;; init returns. Because a gen_server answers no calls until init returns,
;; AuctionAdded is always on disk before any BidAccepted for this auction.
(defun init
  (((list id a at))
   ;; Barrier first: if this process is replacing one that timed out mid
   ;; append, that write may still be queued in the store. `sync' returns only
   ;; once the store has worked past it, so the index read below reflects what
   ;; actually reached disk rather than a snapshot taken too early.
   (event-store:sync)
   (case (event-store:events-for id)
     (()
      (case (event-store:append `#(auction-added ,at ,a))
        ('ok
         (auction-registry:set-auction id a)
         `#(ok ,(map 'auction a 'state (auction:empty-state a))))
        (`#(error ,reason)
         `#(stop ,reason))))
     (events
      (let ((repository (commands:fold-events events)))
        (case (maps:find id repository)
          (`#(ok #(,recovered ,state))
           (auction-registry:set-auction id recovered)
           `#(ok ,(map 'auction recovered 'state state)))
          ('error
           `#(stop #(corrupt-log ,id)))))))))

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
  (('stop _from data)
   `#(stop shutdown ok ,data))
  ((_msg _from data)
   `#(reply #(error "Unknown command.") ,data)))

(defun handle_cast (_msg data) `#(noreply ,data))

(defun handle_info (_msg data) `#(noreply ,data))

(defun terminate (_reason _data) 'ok)

(defun code_change (_old data _extra) `#(ok ,data))
