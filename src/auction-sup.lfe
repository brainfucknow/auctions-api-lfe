;;; Supervisor for the per-auction processes.
;;;
;;; simple_one_for_one restarts a crashed auction with the same arguments it
;;; was started with. Those arguments include the auction record so that a
;;; *first* start can write AuctionAdded; on a restart the log already has
;;; events, so init replays instead and the record is ignored.
(defmodule auction-sup
  (behaviour supervisor)
  ;; supervisor implementation
  (export
   (start_link 0))
  ;; callback implementation
  (export
   (init 1))
  ;; supervisor API
  (export
   (start-auction 3)))

(defun SERVER () (MODULE))

(defun start_link ()
  (supervisor:start_link `#(local ,(SERVER)) (MODULE) '()))

(defun start-auction (id a at)
  (supervisor:start_child (SERVER) (list id a at)))

(defun init (_args)
  `#(ok #(#M(strategy simple_one_for_one
             intensity 5
             period 60)
          (#M(id auction-server
              start #(auction-server start_link ())
              restart transient
              shutdown 5000
              type worker
              modules (auction-server))))))
