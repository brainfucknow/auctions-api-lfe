;;; Append-only event store over a disk_log, plus the ETS index that lets an
;;; auction process rebuild itself without scanning the file.
;;;
;;; Durability contract: `append/1' returns ok only after disk_log:log/2 AND
;;; disk_log:sync/1 have both succeeded, so a bid the client sees as accepted
;;; has reached the device. Haskell queues the event and replies first; see
;;; PARITY.md. There is deliberately no cast path - every caller blocks, which
;;; is what bounds this process's mailbox.
;;;
;;; The sync is the cost, so appends are group-committed: every append
;;; waiting in the mailbox is written in one pass under a single sync.
;;; `{events_fsync, false}' skips the sync; see README.
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
;; Upper bound on appends written under one sync.
(defun MAX-BATCH () 256)

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
       `#(ok ,(initial-state)))
      ((tuple 'repaired _ _ _)
       ;; A torn tail from an unclean shutdown was trimmed on open.
       `#(ok ,(initial-state)))
      ((tuple 'error reason)
       `#(stop ,reason)))))

;; State: the next sequence number and whether to sync after each batch.
(defun initial-state ()
  (map 'seq (build-index) 'fsync (fsync?)))

(defun handle_call
  ;; Group commit: this append plus every append already queued behind it.
  ;; The other callers are answered with gen_server:reply once the batch is
  ;; on disk; this one through the normal return.
  ((`#(append ,event) from state)
   (let* ((batch (cons `#(,from ,event) (drain (- (MAX-BATCH) 1) '())))
          (`#(,replies ,next) (commit batch state)))
     (lists:foreach (lambda (r)
                      (case r
                        (`#(,f ,reply) (when (=/= f from))
                         (gen_server:reply f reply))
                        (_ 'ok)))
                    replies)
     ;; The caller of this handle_call heads the batch.
     `#(reply ,(element 2 (hd replies)) ,next)))
  (('sync _from state)
   `#(reply ok ,state))
  (('stop _from state)
   `#(stop shutdown ok ,state))
  ((_msg _from state)
   `#(reply #(error "Unknown command.") ,state)))

(defun handle_cast (_msg state) `#(noreply ,state))

(defun handle_info (_msg state) `#(noreply ,state))

(defun terminate (_reason _state)
  (disk_log:close (LOG))
  'ok)

(defun code_change (_old state _extra) `#(ok ,state))

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

(defun fsync? ()
  (case (application:get_env 'auctions 'events_fsync)
    ('#(ok false) 'false)
    (_ 'true)))

;; Pull up to n further append requests out of the mailbox without waiting.
;; Other requests stay queued and are answered after this batch, which is
;; still after everything queued ahead of them, so the `sync' barrier holds.
(defun drain (n acc)
  (if (=< n 0)
    (lists:reverse acc)
    (receive
      (`#($gen_call ,from #(append ,event))
       (drain (- n 1) (cons `#(,from ,event) acc)))
      (after 0
        (lists:reverse acc)))))

;; Write every event in the batch, then sync once. Returns #(Replies State)
;; where Replies is a list of #(From Reply) in batch order.
;;
;; log/2 hands the term to the OS; sync/1 pushes it to the device. Each
;; event gets its own log/2 call, so a halt log that fills mid-batch fails
;; only the events that did not fit. If the sync fails, every event written
;; in this pass is reported as failed.
(defun commit (batch state)
  (let* ((fsync (maps:get 'fsync state))
         (`#(,written ,seq2) (write-all batch (maps:get 'seq state))))
    (case (sync-written written fsync)
      ('ok
       (lists:foreach (lambda (w)
                        (case w
                          (`#(,_ ok ,event ,n) (index-event event n))
                          (_ 'ok)))
                      written)
       `#(,(lists:map (lambda (w) `#(,(element 1 w) ,(element 2 w))) written)
          ,(maps:put 'seq seq2 state)))
      (`#(error ,reason)
       `#(,(lists:map (lambda (w) `#(,(element 1 w) #(error ,reason))) written)
          ,(maps:put 'seq seq2 state))))))

;; Returns #(Written NextSeq) with Written a list of
;; #(From ok|#(error Reason) Event Seq) in batch order. A failed write does
;; not consume a sequence number.
(defun write-all (batch seq)
  (let ((`#(,acc ,next)
         (lists:foldl
          (lambda (entry acc-seq)
            (let ((`#(,from ,event) entry)
                  (`#(,acc ,n) acc-seq))
              (case (disk_log:log (LOG) event)
                ('ok `#(,(cons `#(,from ok ,event ,n) acc) ,(+ n 1)))
                (`#(error ,reason)
                 `#(,(cons `#(,from #(error ,reason) ,event ,n) acc) ,n)))))
          `#(() ,seq)
          batch)))
    `#(,(lists:reverse acc) ,next)))

(defun sync-written (written fsync)
  (if (andalso fsync
               (lists:any (lambda (w) (=:= (element 2 w) 'ok)) written))
    (disk_log:sync (LOG))
    'ok))

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
