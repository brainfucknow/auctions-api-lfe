;;; The auction entity. Port of AuctionSite.Domain.Auctions.
(defmodule auction
  (export
   (empty-state 1)
   (validate-bid 2)
   (typ->binary 1)
   (binary->typ 1)))

(include-lib "auctions/include/auctions.lfe")

(defun empty-state (a)
  (case (auction-typ a)
    (`#(single-sealed-bid ,opts)
     (single-sealed-bid:empty-state (auction-expiry a) opts))
    (`#(timed-ascending ,opts)
     (timed-ascending:empty-state (auction-starts-at a) (auction-expiry a) opts))))

(defun validate-bid (bid a)
  (if (=:= (bid-bidder bid) (auction-seller a))
    `#(error #(seller-cannot-place-bids ,(user:user-id (bid-bidder bid))
                                        ,(auction-id a)))
    'ok))

;;; ---------------
;;; string codec
;;; ---------------

(defun typ->binary
  ((`#(timed-ascending ,opts)) (timed-ascending:options->binary opts))
  ((`#(single-sealed-bid ,opts)) (single-sealed-bid:options->binary opts)))

;; Haskell tries TimedAscending first and falls back to SingleSealedBid.
(defun binary->typ (bin)
  (case (timed-ascending:binary->options bin)
    (`#(ok ,opts) `#(ok #(timed-ascending ,opts)))
    (_
     (case (single-sealed-bid:binary->options bin)
       (`#(ok ,opts) `#(ok #(single-sealed-bid ,opts)))
       (_ `#(error #(invalid-auction-type ,bin)))))))
