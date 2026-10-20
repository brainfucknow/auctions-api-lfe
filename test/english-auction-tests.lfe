;;; Port of test/EnglishAuctionSpec.hs.
(defmodule english-auction-tests
  (behaviour ltest-unit)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")
(include-lib "auctions/include/auctions.lfe")

(defun opts () (timed-ascending:default-options))

(defun empty-asc ()
  (auction:empty-state (sample-data:auction-of-typ `#(timed-ascending ,(opts)))))

(defun state-with-1-bid ()
  (auction-state:add-bid (sample-data:bid1) (empty-asc)))

(defun state-with-2-bids ()
  (auction-state:add-bid (sample-data:bid2) (element 1 (state-with-1-bid))))

(defun ended-after-two-bids ()
  (auction-state:inc (sample-data:ends-at) (element 1 (state-with-2-bids))))

;;; ------------------------
;;; english auction states
;;; ------------------------

(deftest can-add-bid-to-empty-state
  (is-equal 'ok (element 2 (state-with-1-bid))))

(deftest can-add-second-bid
  (is-equal 'ok (element 2 (state-with-2-bids))))

(deftest can-end
  (is-equal `#(has-ended () ,(sample-data:ends-at) ,(opts))
            (auction-state:inc (sample-data:ends-at) (empty-asc))))

(deftest ended-with-two-bids
  (is-equal `#(has-ended (,(sample-data:bid2) ,(sample-data:bid1))
               ,(sample-data:ends-at) ,(opts))
            (ended-after-two-bids)))

(deftest cant-bid-after-auction-has-ended
  (is-equal '#(error #(auction-has-ended 1))
            (element 2 (auction-state:add-bid (sample-data:sample-bid)
                                              (ended-after-two-bids)))))

(deftest can-get-winner-and-price-from-an-auction
  (is-equal `#(some ,(sample-data:bid-amount2)
                    ,(user:user-id (sample-data:buyer2)))
            (auction-state:try-get-amount-and-winner (ended-after-two-bids))))

(deftest cant-place-bid-lower-than-highest-bid
  (is-equal `#(error #(must-place-bid-over-highest-bid
                       ,(sample-data:bid-amount2)))
            (element 2 (auction-state:add-bid (sample-data:bid-less-than-2)
                                              (element 1 (state-with-2-bids))))))

(deftestgen increment (increment-spec:tests (empty-asc)))

;;; ------------------------
;;; english auction timing
;;; ------------------------

(deftest transitions-to-ongoing-after-start
  (is-equal `#(on-going () ,(sample-data:ends-at) ,(opts))
            (auction-state:inc (sample-data:bid-time) (empty-asc))))

(deftest cant-bid-before-auction-starts
  (let ((early (set-bid-at (sample-data:bid1) (- (sample-data:starts-at) 1000))))
    (is-equal `#(error #(auction-has-not-started ,(sample-data:sample-auction-id)))
              (element 2 (auction-state:add-bid early (empty-asc))))))

;;; timeFrame extension: a bid landing within the frame pushes expiry out to
;;; bidTime + timeFrame.
(defun tf-opts () (map 'reserve-price 0 'min-raise 0 'time-frame 3600000))

(defun tf-ongoing ()
  (auction-state:inc
   (sample-data:bid-time)
   (auction:empty-state
    (sample-data:auction-of-typ `#(timed-ascending ,(tf-opts))))))

(defun tf-near-end-time () (- (sample-data:ends-at) 1800000))

(defun tf-state-after-bid ()
  (element 1 (auction-state:add-bid
              (set-bid-at (sample-data:bid1) (tf-near-end-time))
              (tf-ongoing))))

(defun tf-extended-expiry () (+ (tf-near-end-time) 3600000))

(deftest bid-near-end-extends-expiry
  (is-equal 'false
            (auction-state:has-ended
             (auction-state:inc (sample-data:ends-at) (tf-state-after-bid)))))

;; `addUTCTime 1' here is one *second*, unlike the picosecond offsets in
;; incrementSpec.
(deftest auction-ends-after-extended-expiry
  (is-equal 'true
            (auction-state:has-ended
             (auction-state:inc (+ (tf-extended-expiry) 1000)
                                (tf-state-after-bid)))))

;;; ------------------------------------
;;; english auction type serialization
;;; ------------------------------------

(deftest can-deserialize-sample-typ
  (is-equal `#(ok ,(opts)) (timed-ascending:binary->options #"English|0|0|0")))

(deftest can-serialize-sample-typ
  (is-equal #"English|0|0|0" (timed-ascending:options->binary (opts))))

(deftest can-deserialize-sample-with-values-typ
  (is-equal `#(ok ,(map 'reserve-price 10 'min-raise 20 'time-frame 30000))
            (timed-ascending:binary->options #"English|10|20|30")))

(deftest can-serialize-sample-with-values-typ
  (is-equal #"English|10|20|30"
            (timed-ascending:options->binary
             (map 'reserve-price 10 'min-raise 20 'time-frame 30000))))
