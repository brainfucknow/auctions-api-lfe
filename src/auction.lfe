;;; The auction entity. Port of AuctionSite.Domain.Auctions.
(defmodule auction
  (export
   (empty-state 1)
   (validate-bid 2)
   (typ->binary 1)
   (binary->typ 1)
   (to-json 1)
   (from-json 1)))

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

;;; ---------------
;;; json codec
;;; ---------------

(defun to-json (a)
  (map #"id"       (auction-id a)
       #"startsAt" (clock:format (auction-starts-at a))
       #"title"    (auction-title a)
       #"expiry"   (clock:format (auction-expiry a))
       #"user"     (user:user->binary (auction-seller a))
       #"type"     (typ->binary (auction-typ a))
       #"currency" (money:currency->binary (auction-currency a))))

(defun from-json
  ((obj) (when (is_map obj))
   (case (list (maps:find #"id" obj)
               (maps:find #"startsAt" obj)
               (maps:find #"title" obj)
               (maps:find #"expiry" obj)
               (maps:find #"user" obj)
               (maps:find #"type" obj)
               (maps:find #"currency" obj))
     ((list `#(ok ,id) `#(ok ,starts) `#(ok ,title) `#(ok ,expiry)
            `#(ok ,user-bin) `#(ok ,typ-bin) `#(ok ,currency-bin))
      (case (list (clock:parse starts) (clock:parse expiry)
                  (user:binary->user user-bin) (binary->typ typ-bin)
                  (money:binary->currency currency-bin))
        ((list `#(ok ,starts-at) `#(ok ,expires-at) `#(ok ,seller)
               `#(ok ,typ) `#(ok ,currency))
         `#(ok ,(make-auction id id
                              starts-at starts-at
                              title title
                              expiry expires-at
                              seller seller
                              typ typ
                              currency currency)))
        (_ `#(error #(invalid-auction ,obj)))))
     (_ `#(error #(invalid-auction ,obj)))))
  ((other)
   `#(error #(invalid-auction ,other))))
