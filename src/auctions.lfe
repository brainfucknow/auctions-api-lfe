;;; Public facade. Port of `handle' in AuctionSite.Domain, with the repository
;;; replaced by the process registry and one process per auction.
(defmodule auctions
  (export
   (add-auction 2)
   (place-bid 2)
   (get 2)
   (list-auctions 0)))

(include-lib "auctions/include/auctions.lfe")

(defun TIMEOUT () 5000)

;; Haskell checks for an existing auction before checking expiry, so a
;; duplicate create of an expired auction reports AuctionAlreadyExists.
(defun add-auction (now a)
  (let ((id (auction-id a)))
    (case (auction-registry:whereis_name id)
      ('undefined
       (if (=< (auction-expiry a) now)
         `#(error #(auction-has-ended ,id))
         (start id a now)))
      (_pid
       `#(error #(auction-already-exists ,id))))))

;; start_child losing the race against a concurrent create is the same
;; outcome as finding the auction above; the registry is what makes that
;; atomic, so no extra locking is needed.
;;
;; start_child returns as soon as the process exists. The auction writes
;; AuctionAdded afterwards and answers `ready' once it has. If the write
;; failed the process is gone and the call exits instead.
(defun start (id a now)
  (case (auction-sup:start-auction id a now)
    (`#(ok ,pid) (await-ready pid now a))
    (`#(error #(already_started ,_)) `#(error #(auction-already-exists ,id)))
    ('#(error already_present) `#(error #(auction-already-exists ,id)))
    (`#(error ,_reason) '#(error event-store-unavailable))))

;; infinity, as start_child was: only the store's barrier can hold this up.
(defun await-ready (pid now a)
  (try
    (progn
      (gen_server:call pid 'ready 'infinity)
      `#(ok #(auction-added ,now ,a)))
    (catch
      ((tuple 'exit _ _) '#(error event-store-unavailable)))))

(defun place-bid (now b)
  (let ((id (bid-auction b)))
    (case (auction-registry:whereis_name id)
      ('undefined `#(error #(auction-not-found ,id)))
      (pid (call-auction pid `#(place-bid ,now ,b) id)))))

(defun get (id now)
  (case (auction-registry:whereis_name id)
    ('undefined `#(error #(auction-not-found ,id)))
    (pid (call-auction pid `#(get ,now) id))))

(defun list-auctions ()
  (auction-registry:auctions))

;;; -----------------
;;; private functions
;;; -----------------

;; A call can fail because the auction died between the registry lookup and
;; the call, or because it was restarted while the store was unavailable.
;; Both are reported as a missing auction or an unavailable store rather than
;; crashing the caller.
(defun call-auction (pid msg id)
  (try
    (gen_server:call pid msg (TIMEOUT))
    (catch
      ((tuple 'exit `#(noproc ,_) _) `#(error #(auction-not-found ,id)))
      ((tuple 'exit `#(shutdown ,_) _) `#(error #(auction-not-found ,id)))
      ((tuple 'exit _ _) '#(error event-store-unavailable)))))
