;;; Single sealed bid (Blind / Vickrey) auction state machine.
;;; Port of AuctionSite.Domain.SingleSealedBid.
;;;
;;; States:
;;;   #(accepting-bids  BidsByUser Expiry Opts)  ; map of user id -> bid
;;;   #(disclosing-bids Bids       Expiry Opts)  ; sorted by amount, descending
;;;
;;; Opts is the atom blind or vickrey.
(defmodule single-sealed-bid
  (export
   (options->binary 1)
   (binary->options 1)
   (empty-state 2)
   (inc 2)
   (add-bid 2)
   (get-bids 1)
   (try-get-amount-and-winner 1)
   (has-ended 1)))

(include-lib "auctions/include/auctions.lfe")

(defun empty-state (expiry opts)
  `#(accepting-bids ,(map) ,expiry ,opts))

;;; ---------------
;;; state machine
;;; ---------------

(defun inc
  ((now (= `#(accepting-bids ,bids ,expiry ,opts) state))
   (if (>= now expiry)
     `#(disclosing-bids ,(disclose bids) ,expiry ,opts)
     state))
  ((_now (= `#(disclosing-bids ,_ ,_ ,_) state))
   state))

(defun add-bid (bid state)
  (let* ((now        (bid-at bid))
         (auction-id (bid-auction bid))
         (bidder-id  (user:user-id (bid-bidder bid)))
         (next       (inc now state)))
    (case next
      (`#(accepting-bids ,bids ,expiry ,opts)
       (if (maps:is_key bidder-id bids)
         (tuple next '#(error already-placed-bid))
         (tuple `#(accepting-bids ,(maps:put bidder-id bid bids) ,expiry ,opts)
                'ok)))
      (`#(disclosing-bids ,_ ,_ ,_)
       (tuple next `#(error #(auction-has-ended ,auction-id)))))))

(defun get-bids
  ((`#(accepting-bids ,bids ,_ ,_)) (elems bids))
  ((`#(disclosing-bids ,bids ,_ ,_)) bids))

;; Blind pays the highest bid; Vickrey pays the second highest, or the only
;; bid when there is just one. The winner is the highest bidder either way.
(defun try-get-amount-and-winner
  ((`#(accepting-bids ,_ ,_ ,_)) 'none)
  ((`#(disclosing-bids ,bids ,_ ,opts))
   (case (tuple opts bids)
     ((tuple 'vickrey (cons highest (cons second _)))
      `#(some ,(bid-amount second) ,(user:user-id (bid-bidder highest))))
     ((tuple 'vickrey (list highest))
      `#(some ,(bid-amount highest) ,(user:user-id (bid-bidder highest))))
     ((tuple 'blind (cons highest _))
      `#(some ,(bid-amount highest) ,(user:user-id (bid-bidder highest))))
     (_ 'none))))

(defun has-ended
  ((`#(disclosing-bids ,_ ,_ ,_)) 'true)
  ((_) 'false))

;;; -----------------
;;; private functions
;;; -----------------

;; Haskell's Map.elems yields bids ordered by user id; `disclose' then applies
;; a stable sort on descending amount, so equal amounts keep user-id order.
(defun elems (bids-by-user)
  (lists:map (lambda (kv) (element 2 kv))
             (lists:keysort 1 (maps:to_list bids-by-user))))

(defun disclose (bids-by-user)
  (lists:sort (lambda (a b) (>= (bid-amount a) (bid-amount b)))
              (elems bids-by-user)))

;;; ---------------
;;; string codec
;;; ---------------

(defun options->binary
  (('blind) #"Blind")
  (('vickrey) #"Vickrey"))

(defun binary->options
  ((#"Blind") #(ok blind))
  ((#"Vickrey") #(ok vickrey))
  ((other) `#(error #(invalid-auction-type ,other))))
