;;; Append-only event store over a disk_log, plus the ETS index that lets an
;;; auction process rebuild itself without scanning the file.
;;;
;;; Durability contract: `append/1' returns ok only after disk_log:log/2 AND
;;; disk_log:sync/1 have both succeeded, so a bid the client sees as accepted
;;; has reached the device. Haskell queues the event and replies first; see
;;; PARITY.md. There is deliberately no cast path - every caller blocks, which
;;; is what bounds this process's mailbox.
(defmodule event-store
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
  ;; store API
  (export
   (append 1)
   (sync 0)
   (events-for 1)
   (added-auctions 0)))

(include-lib "auctions/include/auctions.lfe")

(defun SERVER () (MODULE))
(defun LOG () 'auctions-events)
(defun EVENTS () 'auctions-event-index)
(defun ADDED () 'auctions-auction-order)
(defun TIMEOUT () 5000)

;;; -------------------------
;;; gen_server implementation
;;; -------------------------

(defun start_link ()
  (gen_server:start_link `#(local ,(SERVER)) (MODULE) '() '()))

(defun stop ()
  (gen_server:call (SERVER) 'stop))

;;; ---------------
;;; store API
;;; ---------------

;; Blocks until the event is on disk. #(error Reason) on any failure; an exit
;; on timeout, which the calling auction process deliberately lets propagate.
(defun append (event)
  (gen_server:call (SERVER) `#(append ,event) (TIMEOUT)))

;; Barrier: returns only once this process has drained its mailbox up to this
;; call. An auction that timed out on `append' left its request queued here,
;; and that request arrived before this one, so a gen_server processes it
;; first. Waiting on `sync' therefore guarantees the ETS index already
;; reflects whether the timed-out write landed - which is what makes replay
;; after a timeout trustworthy. Deliberately infinity: a restarting auction
;; must not read a half-settled index.
(defun sync ()
  (gen_server:call (SERVER) 'sync 'infinity))

;; Events for one auction in log order. Read straight from ETS, so replay in
;; an auction's init costs no message to this process.
(defun events-for (id)
  (lists:map (lambda (row) (element 3 row))
             (lists:keysort 2 (ets:lookup (EVENTS) id))))

;; #(AuctionId Auction) for every auction-added event, in log order. This is
;; what the replayer walks at startup.
(defun added-auctions ()
  (lists:map (lambda (row) `#(,(element 2 row) ,(element 3 row)))
             (lists:keysort 1 (ets:tab2list (ADDED)))))

;;; -----------------------
;;; callback implementation
;;; -----------------------

(defun init (_args)
  (erlang:process_flag 'trap_exit 'true)
  (let ((path (events-file)))
    (filelib:ensure_dir path)
    (case (disk_log:open `(#(name ,(LOG))
                           #(file ,path)
                           #(type halt)
                           #(size ,(max-bytes))
                           #(format internal)
                           #(repair true)))
      ((tuple 'ok _)
       `#(ok ,(build-index)))
      ((tuple 'repaired _ _ _)
       ;; A torn tail from an unclean shutdown was trimmed on open.
       `#(ok ,(build-index)))
      ((tuple 'error reason)
       `#(stop ,reason)))))

(defun handle_call
  ((`#(append ,event) _from seq)
   (case (write-event event)
     ('ok
      (index-event event seq)
      `#(reply ok ,(+ seq 1)))
     (`#(error ,reason)
      `#(reply #(error ,reason) ,seq))))
  (('sync _from seq)
   `#(reply ok ,seq))
  (('stop _from seq)
   `#(stop shutdown ok ,seq))
  ((_msg _from seq)
   `#(reply #(error "Unknown command.") ,seq)))

(defun handle_cast (_msg seq) `#(noreply ,seq))

(defun handle_info (_msg seq) `#(noreply ,seq))

(defun terminate (_reason _seq)
  (disk_log:close (LOG))
  'ok)

(defun code_change (_old seq _extra) `#(ok ,seq))

;;; -----------------
;;; private functions
;;; -----------------

;; A halt log refuses further writes once it reaches this size, which is how
;; the tests exercise the write-failure path. Unbounded by default.
(defun max-bytes ()
  (case (application:get_env 'auctions 'events_max_bytes)
    (`#(ok ,n) n)
    ('undefined 'infinity)))

(defun events-file ()
  (case (application:get_env 'auctions 'events_file)
    (`#(ok ,path) path)
    ('undefined "tmp/auctions-events.log")))

;; log/2 hands the term to the OS; sync/1 is what pushes it to the device.
;; Without the sync this would be no more durable than the Haskell worker.
(defun write-event (event)
  (case (disk_log:log (LOG) event)
    ('ok
     (case (disk_log:sync (LOG))
       ('ok 'ok)
       (`#(error ,reason) `#(error ,reason))))
    (`#(error ,reason) `#(error ,reason))))

(defun build-index ()
  (ets:new (EVENTS) '(bag named_table protected #(read_concurrency true)))
  (ets:new (ADDED) '(set named_table protected #(read_concurrency true)))
  (index-chunk (disk_log:chunk (LOG) 'start) 0))

(defun index-chunk
  (('eof seq) seq)
  ((`#(error ,reason) _seq) (error reason))
  ((`#(,cont ,terms) seq)
   (index-chunk (disk_log:chunk (LOG) cont) (index-terms terms seq)))
  ((`#(,cont ,terms ,_badbytes) seq)
   (index-chunk (disk_log:chunk (LOG) cont) (index-terms terms seq))))

(defun index-terms (terms seq)
  (lists:foldl (lambda (event n) (index-event event n) (+ n 1)) seq terms))

(defun index-event (event seq)
  (case event
    (`#(auction-added ,_ ,a)
     (ets:insert (EVENTS) `#(,(auction-id a) ,seq ,event))
     (ets:insert (ADDED) `#(,seq ,(auction-id a) ,a)))
    (`#(bid-accepted ,_ ,b)
     (ets:insert (EVENTS) `#(,(bid-auction b) ,seq ,event)))
    (`#(auction-ended ,_ ,id)
     (ets:insert (EVENTS) `#(,id ,seq ,event))))
  'ok)
