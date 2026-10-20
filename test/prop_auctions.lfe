;;; PropEr model for the two state machines (phase 6, not needed for parity).
;;;
;;; These check invariants no example-based test can: that they hold for every
;;; sequence of bids, not just the handful the Hspec suite happens to use.
;;;
;;; PropEr's ?FORALL is an Erlang macro, so the plain proper:forall/2 API is
;;; used instead - it is what the macro expands to anyway.
(defmodule prop_auctions
  (export all))

(include-lib "auctions/include/auctions.lfe")

(defun BASE () 1500000000000)

(defun buyer (n)
  `#(buyer-or-seller ,(erlang:iolist_to_binary (list #"u" (integer_to_binary n)))
                     #"B"))

;;; -----------------
;;; generators
;;; -----------------

;; A sequence of (bidder, amount) pairs, drawn from a small pool of bidders so
;; that duplicate bidders actually occur.
(defun bid-specs ()
  (proper_types:list
   (proper_types:tuple (list (proper_types:integer 1 4)
                             (proper_types:integer 1 100)))))

;;; -----------------
;;; properties
;;; -----------------

;; An English auction only accepts a bid that beats the standing one, so the
;; bid list - newest first - is strictly decreasing in amount.
(defun prop_english_bids_strictly_decrease ()
  (proper:forall
   (bid-specs)
   (lambda (specs)
     (let ((`#(,state ,_) (apply-specs specs (english-state))))
       (strictly-decreasing
        (lists:map (lambda (b) (bid-amount b)) (auction-state:get-bids state)))))))

;; The standing bid never goes down.
(defun prop_english_highest_never_decreases ()
  (proper:forall
   (bid-specs)
   (lambda (specs)
     (non-decreasing (highest-after-each specs (english-state))))))

;; A sealed auction takes one bid per bidder, however many they send.
(defun prop_sealed_at_most_one_bid_per_user ()
  (proper:forall
   (bid-specs)
   (lambda (specs)
     (let* ((`#(,state ,_) (apply-specs specs (sealed-state)))
            (users (lists:map (lambda (b) (user:user-id (bid-bidder b)))
                              (auction-state:get-bids state))))
       (=:= (length users) (length (lists:usort users)))))))

;; Whatever the machine says it accepted is what a reader can see.
(defun prop_accepted_bids_are_retrievable ()
  (proper:forall
   (bid-specs)
   (lambda (specs)
     (let ((`#(,e-state ,e-accepted) (apply-specs specs (english-state)))
           (`#(,s-state ,s-accepted) (apply-specs specs (sealed-state))))
       (andalso (=:= e-accepted (length (auction-state:get-bids e-state)))
                (=:= s-accepted (length (auction-state:get-bids s-state))))))))

;;; -----------------
;;; helpers
;;; -----------------

(defun english-state ()
  (timed-ascending:empty-state (- (BASE) 1000)
                               (+ (BASE) 1000000)
                               (timed-ascending:default-options)))

(defun sealed-state ()
  (single-sealed-bid:empty-state (+ (BASE) 1000000) 'blind))

;; Returns #(FinalState AcceptedCount). Timestamps step by one millisecond so
;; every bid lands inside the auction window.
(defun apply-specs (specs state)
  (let ((`#(,final ,accepted ,_n)
         (lists:foldl
          (lambda (spec acc)
            (let* ((`#(,st ,ok-count ,n) acc)
                   (`#(,who ,amount) spec)
                   (b (make-bid auction 1
                                bidder (buyer who)
                                at (+ (BASE) n)
                                amount amount))
                   (`#(,next ,result) (auction-state:add-bid b st)))
              (if (=:= result 'ok)
                `#(,next ,(+ ok-count 1) ,(+ n 1))
                `#(,st ,ok-count ,(+ n 1)))))
          `#(,state 0 0)
          specs)))
    `#(,final ,accepted)))

(defun highest-after-each (specs state)
  (lists:reverse
   (element 1
            (lists:foldl
             (lambda (spec acc)
               (let* ((`#(,highs ,st ,n) acc)
                      (`#(,who ,amount) spec)
                      (b (make-bid auction 1
                                   bidder (buyer who)
                                   at (+ (BASE) n)
                                   amount amount))
                      (`#(,next ,result) (auction-state:add-bid b st))
                      (kept (if (=:= result 'ok) next st)))
                 `#(,(cons (top kept) highs) ,kept ,(+ n 1))))
             `#(() ,state 0)
             specs))))

(defun top (state)
  (case (auction-state:get-bids state)
    ((cons b _) (bid-amount b))
    (_ 0)))

(defun strictly-decreasing (xs)
  (case xs
    ((cons a (cons b rest)) (andalso (> a b) (strictly-decreasing (cons b rest))))
    (_ 'true)))

(defun non-decreasing (xs)
  (case xs
    ((cons a (cons b rest)) (andalso (=< a b) (non-decreasing (cons b rest))))
    (_ 'true)))
