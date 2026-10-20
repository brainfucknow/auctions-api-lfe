;;; Port of test/VickreyAuctionSpec.hs.
(defmodule vickrey-auction-tests
  (behaviour ltest-unit)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")

(defun empty-vickrey ()
  (auction:empty-state (sample-data:auction-of-typ '#(single-sealed-bid vickrey))))

(defun state-with-1-bid ()
  (auction-state:add-bid (sample-data:bid1) (empty-vickrey)))

(defun state-with-2-bids ()
  (auction-state:add-bid (sample-data:bid2) (element 1 (state-with-1-bid))))

(defun ended-after-two-bids ()
  (auction-state:inc (sample-data:ends-at) (element 1 (state-with-2-bids))))

(deftest can-add-bid-to-empty-state
  (is-equal 'ok (element 2 (state-with-1-bid))))

(deftest can-add-second-bid
  (is-equal 'ok (element 2 (state-with-2-bids))))

(deftest can-end
  (is-equal `#(disclosing-bids (,(sample-data:bid2) ,(sample-data:bid1))
               ,(sample-data:ends-at) vickrey)
            (ended-after-two-bids)))

;; Vickrey: the highest bidder wins but pays the second-highest amount.
(deftest can-get-winner-and-price-from-an-ended-auction
  (is-equal `#(some ,(sample-data:bid-amount1)
                    ,(user:user-id (sample-data:buyer2)))
            (auction-state:try-get-amount-and-winner (ended-after-two-bids))))

(deftestgen increment (increment-spec:tests (empty-vickrey)))

(deftest can-deserialize-sample-typ
  (is-equal '#(ok vickrey) (single-sealed-bid:binary->options #"Vickrey")))

(deftest can-serialize-sample-typ
  (is-equal #"Vickrey" (single-sealed-bid:options->binary 'vickrey)))

(deftest can-deserialize-sample-with-values-typ
  (is-equal '#(ok blind) (single-sealed-bid:binary->options #"Blind")))

(deftest can-serialize-sample-with-values-typ
  (is-equal #"Blind" (single-sealed-bid:options->binary 'blind)))
