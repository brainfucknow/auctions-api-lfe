;;; Dispatch over the two auction families. Port of the State typeclass and
;;; its Either instance in AuctionSite.Domain.States.
;;;
;;; The two families use disjoint state tags, so the Left/Right wrapper
;;; Haskell needs to compose them is unnecessary here.
(defmodule auction-state
  (export
   (family 1)
   (inc 2)
   (add-bid 2)
   (get-bids 1)
   (try-get-amount-and-winner 1)
   (has-ended 1)))

(defun family
  ((`#(awaiting-start ,_ ,_ ,_))  'timed-ascending)
  ((`#(on-going ,_ ,_ ,_))        'timed-ascending)
  ((`#(has-ended ,_ ,_ ,_))       'timed-ascending)
  ((`#(accepting-bids ,_ ,_ ,_))  'single-sealed-bid)
  ((`#(disclosing-bids ,_ ,_ ,_)) 'single-sealed-bid))

(defun inc (now state)
  (call (family state) 'inc now state))

(defun add-bid (bid state)
  (call (family state) 'add-bid bid state))

(defun get-bids (state)
  (call (family state) 'get-bids state))

(defun try-get-amount-and-winner (state)
  (call (family state) 'try-get-amount-and-winner state))

(defun has-ended (state)
  (call (family state) 'has-ended state))
