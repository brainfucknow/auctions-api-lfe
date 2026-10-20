;;; Startup replay: walk the event store's index in log order and start one
;;; auction process per AuctionAdded.
;;;
;;; Each child rebuilds its own state from the log in its init, so this module
;;; only has to decide *which* auctions exist. It does its work during
;;; start_link and then returns `ignore', leaving no process behind; the top
;;; supervisor re-runs it whenever the event store is restarted.
(defmodule event-replayer
  (export
   (start_link 0)
   (replay 0)))

(defun start_link ()
  (replay)
  'ignore)

(defun replay ()
  (let ((added (event-store:added-auctions)))
    (lists:foreach
     (lambda (entry)
       (case entry
         (`#(,id ,a)
          ;; `at' is only used when the log has no events for this auction,
          ;; which cannot happen here, so any value would do.
          (case (auction-sup:start-auction id a (auction-at a))
            (`#(ok ,_pid) 'ok)
            (`#(error ,reason)
             (logger:error "could not replay auction ~p: ~p" (list id reason)))))))
     added)
    (length added)))

(defun auction-at (a) (element 3 a))
