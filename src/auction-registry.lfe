;;; Process registry for auctions, usable as a `via' module.
;;;
;;; Owns a public ETS table of #(AuctionId Pid Auction). The auction record is
;;; kept alongside the pid so GET /auctions can list every auction without
;;; sending a message to a single auction process. The table is an
;;; ordered_set so that listing comes out in id order without a sort.
;;;
;;; The table is owned by this gen_server, so losing it takes down everything
;;; started after it under the top supervisor's rest_for_one strategy.
(defmodule auction-registry
  (behaviour gen_server)
  ;; gen_server implementation
  (export
   (start_link 0)
   (stop 0))
  ;; callback implementation
  (export
   (init 1)
   (handle_call 3)
   (handle_cast 2)
   (handle_info 2)
   (terminate 2)
   (code_change 3))
  ;; `via' callbacks
  (export
   (register_name 2)
   (unregister_name 1)
   (whereis_name 1)
   (send 2))
  ;; registry API
  (export
   (set-auction 2)
   (release 1)
   (lookup 1)
   (auctions 0)))

(defun SERVER () (MODULE))
(defun TABLE () 'auctions-registry)

;;; -------------------------
;;; gen_server implementation
;;; -------------------------

(defun start_link ()
  (gen_server:start_link `#(local ,(SERVER)) (MODULE) '() '()))

(defun stop ()
  (gen_server:call (SERVER) 'stop))

(defun init (_args)
  (ets:new (TABLE)
           '(ordered_set named_table public #(read_concurrency true)))
  `#(ok ,(map)))

;;; -----------------
;;; `via' callbacks
;;; -----------------

;; insert_new is the atomic step that decides a race between two concurrent
;; creates of the same auction id. A losing caller gets 'no, which the facade
;; reports as AuctionAlreadyExists.
(defun register_name (id pid)
  (case (ets:insert_new (TABLE) `#(,id ,pid undefined))
    ('true
     (gen_server:cast (SERVER) `#(monitor ,id ,pid))
     'yes)
    ('false
     (case (ets:lookup (TABLE) id)
       ((list (= `#(,_ ,old ,_) row))
        (if (is_process_alive old)
          'no
          ;; A restart beat the registry's DOWN message; drop the stale row.
          ;; delete_object removes exactly this tuple, so a registration that
          ;; landed in between is left alone.
          (progn
            (ets:delete_object (TABLE) row)
            (register_name id pid))))
       (_ 'no)))))

(defun unregister_name (id)
  (ets:delete (TABLE) id)
  id)

(defun whereis_name (id)
  (case (ets:lookup (TABLE) id)
    ((list `#(,_ ,pid ,_)) pid)
    (_ 'undefined)))

(defun send (id msg)
  (case (whereis_name id)
    ('undefined (exit `#(badarg #(,id ,msg))))
    (pid (! pid msg) pid)))

;;; ---------------
;;; registry API
;;; ---------------

(defun set-auction (id a)
  (ets:update_element (TABLE) id `(#(3 ,a)))
  'ok)

;; Remove the caller's own row now, rather than when the DOWN message
;; arrives. An auction that gives up calls this before it stops, so the id
;; is free again by the time the caller of the create sees the failure.
;; Matching on self() leaves a newer registration alone.
(defun release (id)
  (ets:match_delete (TABLE) `#(,id ,(self) _))
  'ok)

(defun lookup (id)
  (case (ets:lookup (TABLE) id)
    ((list `#(,_ ,pid ,a)) `#(ok #(,pid ,a)))
    (_ 'error)))

;; Auctions in id order (the table's key order), skipping any process that
;; has registered but not yet published its record.
(defun auctions ()
  (lists:filtermap
   (lambda (row)
     (case row
       (`#(,_ ,_ undefined) 'false)
       (`#(,_ ,_ ,a) `#(true ,a))))
   (ets:tab2list (TABLE))))

;;; -----------------------
;;; callback implementation
;;; -----------------------

(defun handle_call
  (('stop _from state) `#(stop shutdown ok ,state))
  ((_msg _from state) `#(reply #(error "Unknown command.") ,state)))

(defun handle_cast
  ((`#(monitor ,id ,pid) state)
   (let ((ref (erlang:monitor 'process pid)))
     `#(noreply ,(maps:put ref id state))))
  ((_msg state) `#(noreply ,state)))

(defun handle_info
  ((`#(DOWN ,ref process ,pid ,_reason) state)
   (case (maps:find ref state)
     (`#(ok ,id)
      (case (ets:lookup (TABLE) id)
        ((list (= `#(,_ ,p ,_) row)) (when (=:= p pid))
         (ets:delete_object (TABLE) row))
        (_ 'ok))
      `#(noreply ,(maps:remove ref state)))
     ('error `#(noreply ,state))))
  ((_msg state) `#(noreply ,state)))

(defun terminate (_reason _state) 'ok)

(defun code_change (_old state _extra) `#(ok ,state))
