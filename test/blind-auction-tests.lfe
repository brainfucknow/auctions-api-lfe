;;; Port of test/BlindAuctionStateSpec.hs.
(defmodule blind-auction-tests
  (behaviour ltest-unit)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")

(defun empty-blind ()
  (auction:empty-state (sample-data:auction-of-typ '#(single-sealed-bid blind))))

(defun state-with-1-bid ()
  (auction-state:add-bid (sample-data:bid1) (empty-blind)))

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
               ,(sample-data:ends-at) blind)
            (ended-after-two-bids)))

;; Blind: the highest bidder wins and pays their own bid.
(deftest can-get-winner-and-price-from-an-ended-auction
  (is-equal `#(some ,(sample-data:bid-amount2)
                    ,(user:user-id (sample-data:buyer2)))
            (auction-state:try-get-amount-and-winner (ended-after-two-bids))))

(deftestgen increment (increment-spec:tests (empty-blind)))
