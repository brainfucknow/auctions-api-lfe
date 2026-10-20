;;; Bid JSON codec. Port of AuctionSite.Domain.Bids.
;;;
;;; The record lives in include/auctions.lfe. Note the bidder serializes under
;;; the key "user", and that extra keys (such as the "id" carried by
;;; sample-commands.jsonl) are ignored on the way in.
(defmodule bid
  (export
   (to-json 1)
   (from-json 1)))

(include-lib "auctions/include/auctions.lfe")

(defun to-json (b)
  (map #"auction" (bid-auction b)
       #"user"    (user:user->binary (bid-bidder b))
       #"at"      (clock:format (bid-at b))
       #"amount"  (bid-amount b)))

(defun from-json
  ((obj) (when (is_map obj))
   (case (list (maps:find #"auction" obj)
               (maps:find #"user" obj)
               (maps:find #"at" obj)
               (maps:find #"amount" obj))
     ((list `#(ok ,auction-id) `#(ok ,user-bin) `#(ok ,at-bin) `#(ok ,amount))
      (case (list (user:binary->user user-bin) (clock:parse at-bin))
        ((list `#(ok ,bidder) `#(ok ,at))
         `#(ok ,(make-bid auction auction-id bidder bidder at at amount amount)))
        (_ `#(error #(invalid-bid ,obj)))))
     (_ `#(error #(invalid-bid ,obj)))))
  ((other)
   `#(error #(invalid-bid ,other))))
