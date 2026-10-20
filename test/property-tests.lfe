;;; Runs the PropEr properties as part of the normal suite.
;;;
;;; rebar3_proper only discovers properties in `.erl' files, so it cannot see
;;; an LFE property module. Driving proper:quickcheck/2 from ltest keeps one
;;; test command for the whole project instead of adding an Erlang shim.
(defmodule property-tests
  (behaviour ltest-unit)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")

(defun TESTS () 200)

(defun check (property)
  (proper:quickcheck property `(#(numtests ,(TESTS)) quiet)))

(deftest english-bids-strictly-decrease
  (is-equal 'true (check (prop_auctions:prop_english_bids_strictly_decrease))))

(deftest english-highest-never-decreases
  (is-equal 'true (check (prop_auctions:prop_english_highest_never_decreases))))

(deftest sealed-takes-at-most-one-bid-per-user
  (is-equal 'true (check (prop_auctions:prop_sealed_at_most_one_bid_per_user))))

(deftest accepted-bids-are-retrievable
  (is-equal 'true (check (prop_auctions:prop_accepted_bids_are_retrievable))))
