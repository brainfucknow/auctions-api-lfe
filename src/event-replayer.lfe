;;; Startup replay: walk the event store's index in log order and start one
;;; auction process per AuctionAdded.
;;;
;;; Each child rebuilds its own state from the log, so this module only has to
;;; decide *which* auctions exist. It does its work during start_link and then
;;; returns `ignore', leaving no process behind; the top supervisor re-runs it
;;; whenever the event store is restarted.
;;;
;;; A child recovers in handle_continue, after start_child has returned, so
;;; replay waits for every child's `ready' before it returns. Until then a
;;; child's registry row has no auction and GET /auctions would skip it.
(defmodule event-replayer
  (export
   (start_link 0)
   (replay 0)))

(defun start_link ()
  (replay)
  'ignore)

(defun replay ()
  (let* ((added (event-store:added-auctions))
         ;; Start them all before waiting on any, so they recover in parallel.
         (pids (lists:filtermap #'start/1 added)))
    (lists:foreach #'await-ready/1 pids)
    (length added)))

(defun start
  ((`#(,id ,a))
   ;; `at' is only used when the log has no events for this auction, which
   ;; cannot happen here, so any value would do.
   (case (auction-sup:start-auction id a (auction-at a))
     (`#(ok ,pid) `#(true #(,id ,pid)))
     (`#(error ,reason)
      (logger:error "could not replay auction ~p: ~p" (list id reason))
      'false))))

;; A child that gives up during recovery stops instead of answering; it has
;; already logged why, so that is not a reason to fail startup.
(defun await-ready
  ((`#(,id ,pid))
   (try
     (gen_server:call pid 'ready 'infinity)
     (catch
       ((tuple 'exit reason _)
        (logger:error "could not replay auction ~p: ~p" (list id reason)))))))

(defun auction-at (a) (element 3 a))
