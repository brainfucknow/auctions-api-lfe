;;; Timed ascending (English) auction state machine.
;;; Port of AuctionSite.Domain.TimedAscending.
;;;
;;; States, with bids held newest-first as in Haskell:
;;;   #(awaiting-start Start Expiry Opts)
;;;   #(on-going       Bids  Expiry Opts)
;;;   #(has-ended      Bids  Expiry Opts)
;;;
;;; Opts is #M(reserve-price Int min-raise Int time-frame Ms). `time-frame' is
;;; milliseconds internally but serializes as whole seconds, matching Haskell's
;;; NominalDiffTime rendering.
(defmodule timed-ascending
  (export
   (default-options 0)
   (options->binary 1)
   (binary->options 1)
   (empty-state 3)
   (inc 2)
   (add-bid 2)
   (get-bids 1)
   (try-get-amount-and-winner 1)
   (has-ended 1)))

(include-lib "auctions/include/auctions.lfe")

(defun default-options ()
  (map 'reserve-price 0 'min-raise 0 'time-frame 0))

(defun empty-state (start expiry opts)
  `#(awaiting-start ,start ,expiry ,opts))

;;; state machine

(defun inc
  ((now (= `#(awaiting-start ,start ,expiry ,opts) state))
   (cond ((and (> now start) (< now expiry)) `#(on-going () ,expiry ,opts))
         ((> now start)                      `#(has-ended () ,expiry ,opts))
         ('true                              state)))
  ((now (= `#(on-going ,bids ,expiry ,opts) state))
   (if (< now expiry) state `#(has-ended ,bids ,expiry ,opts)))
  ((_now (= `#(has-ended ,_ ,_ ,_) state))
   state))

;; Returns #(State Result). Note that a *rejected* bid still yields the
;; time-incremented state, exactly as in Haskell: a bid arriving after the
;; start can move an auction from AwaitingStart to OnGoing even when it fails.
(defun add-bid (bid state)
  (let* ((now        (bid-at bid))
         (auction-id (bid-auction bid))
         (b-amount   (bid-amount bid))
         (next       (inc now state)))
    (case next
      (`#(awaiting-start ,_ ,_ ,_)
       (tuple next `#(error #(auction-has-not-started ,auction-id))))
      (`#(on-going ,bids ,next-expiry ,opts)
       (let ((extended (max next-expiry (+ now (maps:get 'time-frame opts)))))
         (case bids
           (()
            (tuple `#(on-going (,bid) ,extended ,opts) 'ok))
           ((cons highest _)
            (let ((highest-amount (bid-amount highest)))
              (if (> b-amount (+ highest-amount (maps:get 'min-raise opts)))
                (tuple `#(on-going ,(cons bid bids) ,extended ,opts) 'ok)
                (tuple next `#(error #(must-place-bid-over-highest-bid
                                       ,highest-amount)))))))))
      (`#(has-ended ,_ ,_ ,_)
       (tuple next `#(error #(auction-has-ended ,auction-id)))))))

(defun get-bids
  ((`#(on-going ,bids ,_ ,_)) bids)
  ((`#(has-ended ,bids ,_ ,_)) bids)
  ((`#(awaiting-start ,_ ,_ ,_)) '()))

;; A winner exists only once the auction has ended with at least one bid whose
;; amount strictly exceeds the reserve price.
(defun try-get-amount-and-winner
  ((`#(has-ended ,bids ,_ ,opts))
   (case bids
     ((cons highest _)
      (if (< (maps:get 'reserve-price opts) (bid-amount highest))
        `#(some ,(bid-amount highest) ,(user:user-id (bid-bidder highest)))
        'none))
     (_ 'none)))
  ((_) 'none))

(defun has-ended
  ((`#(has-ended ,_ ,_ ,_)) 'true)
  ((_) 'false))

;;; string codec

(defun options->binary (opts)
  (erlang:iolist_to_binary
   (list #"English|"
         (integer_to_binary (maps:get 'reserve-price opts)) #"|"
         (integer_to_binary (maps:get 'min-raise opts)) #"|"
         (integer_to_binary (div (maps:get 'time-frame opts) 1000)))))

(defun binary->options (bin)
  (case (binary:split bin #"|" '(global))
    ((list #"English" a b c)
     (case (list (to-int a) (to-int b) (to-int c))
       ((list `#(ok ,reserve) `#(ok ,raise) `#(ok ,seconds))
        `#(ok ,(map 'reserve-price reserve
                    'min-raise raise
                    'time-frame (* seconds 1000))))
       (_ `#(error #(invalid-auction-type ,bin)))))
    (_ `#(error #(invalid-auction-type ,bin)))))

(defun to-int (bin)
  (try
    `#(ok ,(binary_to_integer bin))
    (catch ((tuple _ _ _) 'error))))
