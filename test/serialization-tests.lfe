;;; Port of test/SerializationSpec.hs.
(defmodule serialization-tests
  (behaviour ltest-unit)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")

(defun samples () "./test/samples/sample-commands.jsonl")
(defun tmp-samples () "./tmp/sample-commands.jsonl")

(defun add-auction ()
  `#(add-auction ,(sample-data:starts-at) ,(sample-data:auction)))

(defun place-bid ()
  `#(place-bid ,(sample-data:bid-time) ,(sample-data:bid1)))

(defun timed-ascending-typ ()
  `#(timed-ascending ,(timed-ascending:default-options)))

;;; -----------
;;; read json
;;; -----------

(deftest reading-commands-from-jsonl
  (is-not-equal 'none (json-lines:read-commands (samples))))

(deftest can-deserialize-type
  (is-equal `#(ok ,(timed-ascending-typ))
            (auction:binary->typ (json:decode #"\"English|0|0|0\""))))

(deftest read-add-auction
  (is-match `#(ok #(add-auction ,_ ,_))
            (commands:command-from-json
             (json:decode #"{\"$type\":\"AddAuction\",\"at\":\"2020-05-17T08:15:16.464Z\",\"auction\":{\"id\":1,\"startsAt\":\"2018-12-01T10:00:00.000Z\",\"title\":\"Some auction\",\"expiry\":\"2020-05-18T10:00:00.000Z\",\"user\":\"BuyerOrSeller|a1|Test\",\"type\":\"English|0|0|0\",\"currency\":\"VAC\"}}"))))

;; The bid object carries an "id" the decoder must ignore.
(deftest read-place-bid
  (is-match `#(ok #(place-bid ,_ ,_))
            (commands:command-from-json
             (json:decode #"{\"$type\":\"PlaceBid\",\"at\":\"2020-05-17T08:15:22.948Z\",\"bid\":{\"id\":\"32e692cc3fdb451da9647d6eeca5b2e3\",\"auction\":1,\"user\":\"BuyerOrSeller|a2|Buyer\",\"amount\":11,\"at\":\"2020-05-17T08:15:22.940Z\"}}"))))

;;; -------
;;; parse
;;; -------

(deftest can-parse-amount
  (is-equal '#(ok #(amount vac 0)) (money:binary->amount #"VAC0")))

(deftest can-parse-and-write-amount
  (is-equal '#(ok #(amount vac 0))
            (money:binary->amount (money:amount->binary '#(amount vac 0)))))

(deftest can-write-auctiontype
  (is-equal `#(ok ,(timed-ascending-typ))
            (auction:binary->typ (auction:typ->binary (timed-ascending-typ)))))

(deftest can-read-auctiontype
  (is-equal `#(ok ,(timed-ascending-typ))
            (auction:binary->typ #"English|0|0|0")))

;;; ------------
;;; write json
;;; ------------

(deftest can-serialize-add-auction
  (is-equal (json:decode #"{\"$type\":\"AddAuction\",\"at\":\"2016-01-01T08:28:00.607Z\",\"auction\":{\"expiry\":\"2016-02-01T08:28:00.607Z\",\"startsAt\":\"2016-01-01T08:28:00.607Z\",\"user\":\"BuyerOrSeller|Sample_Seller|Seller\",\"currency\":\"SEK\",\"id\":1,\"title\":\"auction\",\"type\":\"Vickrey\"}}")
            (commands:command-to-json (add-auction))))

;; Haskell expects ...607875000001Z for the bid time; at millisecond
;; resolution that one-picosecond offset becomes one millisecond. See PARITY.md.
(deftest can-serialize-place-bid
  (is-equal (json:decode #"{\"$type\":\"PlaceBid\",\"at\":\"2016-02-01T07:28:00.607Z\",\"bid\":{\"amount\":10,\"at\":\"2016-01-01T08:28:00.608Z\",\"auction\":1,\"user\":\"BuyerOrSeller|Buyer_1|Buyer 1\"}}")
            (commands:command-to-json (place-bid))))

;;; ---------------------
;;; read and write json
;;; ---------------------

(deftest read-and-write-commands-round-trip
  (filelib:ensure_dir (tmp-samples))
  (file:delete (tmp-samples))
  (let ((`#(ok ,cmds) (json-lines:read-commands (samples))))
    (let ((`#(,first-four ,rest) (lists:split 4 cmds)))
      (json-lines:write-commands (tmp-samples) first-four)
      (json-lines:write-commands (tmp-samples) rest)
      (is-equal `#(ok ,cmds) (json-lines:read-commands (tmp-samples))))))
