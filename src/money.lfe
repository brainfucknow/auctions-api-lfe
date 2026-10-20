;;; Currencies and amounts. Port of AuctionSite.Money.
;;;
;;; Currencies are lowercase atoms internally and uppercase binaries on the
;;; wire. An amount is #(amount Currency Value); bid amounts in the domain are
;;; plain integers (Haskell's AmountValue), not Amounts.
(defmodule money
  (export
   (currencies 0)
   (currency->binary 1)
   (binary->currency 1)
   (amount->binary 1)
   (binary->amount 1)
   (amount-currency 1)
   (amount-value 1)
   (add 2)))

(defun currencies () '(vac sek dkk))

(defun currency->binary
  (('vac) #"VAC")
  (('sek) #"SEK")
  (('dkk) #"DKK"))

(defun binary->currency
  ((#"VAC") #(ok vac))
  ((#"SEK") #(ok sek))
  ((#"DKK") #(ok dkk))
  ((other) `#(error #(invalid-currency ,other))))

(defun amount-currency
  ((`#(amount ,c ,_)) c))

(defun amount-value
  ((`#(amount ,_ ,v)) v))

(defun amount->binary
  ((`#(amount ,c ,v))
   (erlang:iolist_to_binary
    (list (currency->binary c) (integer_to_binary v)))))

;; Haskell reads an Amount as `many letter' followed by `many digit', so the
;; value is never negative here.
(defun binary->amount (bin)
  (case (re:run bin "^([A-Za-z]+)([0-9]+)$" '(#(capture all_but_first binary)))
    (`#(match (,cur ,val))
     (case (binary->currency cur)
       (`#(ok ,c) `#(ok #(amount ,c ,(binary_to_integer val))))
       (_ `#(error #(invalid-amount ,bin)))))
    ('nomatch `#(error #(invalid-amount ,bin)))))

(defun add
  ((`#(amount ,ac ,av) `#(amount ,bc ,bv)) (when (=:= ac bc))
   `#(amount ,ac ,(+ av bv)))
  ((_ _)
   (error "Cant add two amounts with different currency")))
