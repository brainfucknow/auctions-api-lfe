;;; Request bodies for the HTTP layer. Port of AuctionSite.Web.Types.
;;;
;;; A create request reads "endsAt" and an optional "typ", where the stored
;;; auction serializes with "expiry" and "type". Currency defaults to VAC and
;;; the type to an English auction with default options, as in Haskell.
(defmodule web-types
  (export
   (add-auction-req 1)
   (bid-req 1)
   (api-error 1)
   (auction-list-item 1)
   (auction-detail 2)
   (bid-item 1)))

(include-lib "auctions/include/auctions.lfe")

(defun api-error (message)
  (map #"message" message))

(defun bid-req
  ((obj) (when (is_map obj))
   (case (maps:find #"amount" obj)
     (`#(ok ,amount) (when (is_integer amount)) `#(ok ,amount))
     (_ `#(error #(invalid-bid-request ,obj)))))
  ((other)
   `#(error #(invalid-bid-request ,other))))

(defun add-auction-req
  ((obj) (when (is_map obj))
   (case (list (maps:find #"id" obj)
               (maps:find #"startsAt" obj)
               (maps:find #"title" obj)
               (maps:find #"endsAt" obj))
     ((list `#(ok ,id) `#(ok ,starts) `#(ok ,title) `#(ok ,ends))
      (case (list (clock:parse starts)
                  (clock:parse ends)
                  (currency obj)
                  (typ obj))
        ((list `#(ok ,starts-at) `#(ok ,ends-at) `#(ok ,currency) `#(ok ,typ))
         `#(ok ,(map 'id id
                     'starts-at starts-at
                     'title title
                     'ends-at ends-at
                     'currency currency
                     'typ typ)))
        (_ `#(error #(invalid-auction-request ,obj)))))
     (_ `#(error #(invalid-auction-request ,obj)))))
  ((other)
   `#(error #(invalid-auction-request ,other))))

(defun currency (obj)
  (case (maps:find #"currency" obj)
    ('error #(ok vac))
    (`#(ok ,bin) (money:binary->currency bin))))

(defun typ (obj)
  (case (maps:find #"typ" obj)
    ('error `#(ok #(timed-ascending ,(timed-ascending:default-options))))
    (`#(ok ,bin) (auction:binary->typ bin))))

;;; ---------------
;;; responses
;;; ---------------

(defun auction-list-item (a)
  (map #"id"       (auction-id a)
       #"startsAt" (clock:format (auction-starts-at a))
       #"title"    (auction-title a)
       #"expiry"   (clock:format (auction-expiry a))
       #"currency" (money:currency->binary (auction-currency a))))

(defun bid-item (b)
  (map #"amount" (bid-amount b)
       #"bidder" (user:user->binary (bid-bidder b))))

;; The detail view is the list item plus the bids, the winner and the price
;; the winner pays. `winner' and `winnerPrice' are null until an auction has
;; ended with a bid that clears the reserve.
(defun auction-detail (a state)
  (let ((`#(,winner ,winner-price)
         (case (auction-state:try-get-amount-and-winner state)
           (`#(some ,amount ,who) `#(,who ,amount))
           ('none #(null null)))))
    (maps:merge
     (auction-list-item a)
     (map #"bids" (lists:map (lambda (b) (bid-item b))
                             (auction-state:get-bids state))
          #"winner" winner
          #"winnerPrice" winner-price))))
