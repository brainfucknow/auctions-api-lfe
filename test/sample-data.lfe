;;; Port of test/SampleData.hs.
;;;
;;; Timestamps are truncated to milliseconds (.607875 -> .607) and the bid
;;; offsets that Haskell writes as `addUTCTime (toEnum 1)' - one picosecond -
;;; become one millisecond. See PARITY.md.
(defmodule sample-data
  (export all))

(include-lib "auctions/include/auctions.lfe")

(defun ms (iso)
  (calendar:rfc3339_to_system_time iso '(#(unit millisecond))))

(defun sample-auction-id () 1)
(defun title () #"auction")
(defun starts-at () (ms "2016-01-01T08:28:00.607Z"))
(defun ends-at ()   (ms "2016-02-01T08:28:00.607Z"))
(defun bid-time ()  (ms "2016-02-01T07:28:00.607Z"))

(defun seller () #(buyer-or-seller #"Sample_Seller" #"Seller"))
(defun buyer ()  #(buyer-or-seller #"Sample_Buyer" #"Buyer"))
(defun buyer1 () #(buyer-or-seller #"Buyer_1" #"Buyer 1"))
(defun buyer2 () #(buyer-or-seller #"Buyer_2" #"Buyer 2"))
(defun buyer3 () #(buyer-or-seller #"Buyer_3" #"Buyer 3"))

(defun auction-of-typ (typ)
  (make-auction id (sample-auction-id)
                title (title)
                starts-at (starts-at)
                expiry (ends-at)
                seller (seller)
                currency 'sek
                typ typ))

(defun auction () (auction-of-typ #(single-sealed-bid vickrey)))

(defun sample-bid ()
  (make-bid auction (sample-auction-id) bidder (buyer) at (bid-time) amount 100))

(defun bid-amount1 () 10)
(defun bid-amount2 () 12)

(defun bid1 ()
  (make-bid auction (sample-auction-id) bidder (buyer1)
            at (+ (starts-at) 1) amount (bid-amount1)))

(defun bid2 ()
  (make-bid auction (sample-auction-id) bidder (buyer2)
            at (+ (starts-at) 2) amount (bid-amount2)))

(defun bid-less-than-2 ()
  (make-bid auction (sample-auction-id) bidder (buyer3)
            at (+ (starts-at) 3) amount 11))
