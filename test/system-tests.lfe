;;; System tests for the OTP layer: they start the real application, with a
;;; real disk_log, and exercise create / bid / read / recover.
(defmodule system-tests
  (behaviour ltest-system)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")
(include-lib "auctions/include/auctions.lfe")

(defun english () `#(timed-ascending ,(timed-ascending:default-options)))
(defun a-seller () #(buyer-or-seller #"seller" #"Seller"))

(defun a-buyer (n)
  `#(buyer-or-seller ,(erlang:iolist_to_binary (list #"b" (integer_to_binary n)))
                     #"Buyer"))

(defun an-auction (id now)
  (make-auction id id
                starts-at (- now 1000)
                title #"Test auction"
                expiry (+ now 3600000)
                seller (a-seller)
                typ (english)
                currency 'sek))

(defun a-bid (id n now amount)
  (make-bid auction id bidder (a-buyer n) at now amount amount))

(defun bids-of (id now)
  (let ((`#(ok #(,_a ,state)) (auctions:get id now)))
    (auction-state:get-bids state)))

;;; -----------------
;;; app lifecycle
;;; -----------------

(defun stop-app ()
  (application:stop 'auctions)
  (application:unload 'auctions)
  'ok)

(defun start-app (file opts)
  (catch (application:load 'auctions))
  (application:set_env 'auctions 'events_file file)
  (case (maps:find 'max-bytes opts)
    (`#(ok ,n) (application:set_env 'auctions 'events_max_bytes n))
    ('error (application:unset_env 'auctions 'events_max_bytes)))
  (let ((`#(ok ,_) (application:ensure_all_started 'auctions)))
    'ok))

(defun with-app (name f) (with-app name (map) f))

(defun with-app (name opts f)
  (let ((file (++ "tmp/" name "-events.log")))
    (catch (stop-app))
    (filelib:ensure_dir file)
    (file:delete file)
    (start-app file opts)
    (try
      (funcall f file)
      (after (catch (stop-app))))))

(defun log-tags (file)
  (let ((`#(ok ,_) (disk_log:open `(#(name inspect-log)
                                    #(file ,file)
                                    #(mode read_only)))))
    (let ((tags (case (disk_log:chunk 'inspect-log 'start)
                  ('eof '())
                  (`#(,_cont ,terms) (lists:map (lambda (t) (element 1 t)) terms)))))
      (disk_log:close 'inspect-log)
      tags)))

;;; -----------------
;;; tests
;;; -----------------

(deftest create-bid-read-and-list
  (with-app "create"
    (lambda (_file)
      (let ((now (clock:now)))
        (is-match `#(ok #(auction-added ,_ ,_))
                  (auctions:add-auction now (an-auction 1 now)))
        (is-match `#(ok ,_) (auctions:place-bid (+ now 1) (a-bid 1 1 (+ now 1) 10)))
        (is-match `#(ok ,_) (auctions:place-bid (+ now 2) (a-bid 1 2 (+ now 2) 20)))
        (is-equal 2 (length (bids-of 1 (+ now 10))))
        (is-equal 1 (length (auctions:list-auctions)))))))

(deftest duplicate-create-is-rejected
  (with-app "dup"
    (lambda (_file)
      (let ((now (clock:now)))
        (is-match `#(ok ,_) (auctions:add-auction now (an-auction 1 now)))
        (is-equal '#(error #(auction-already-exists 1))
                  (auctions:add-auction now (an-auction 1 now)))))))

(deftest create-of-an-expired-auction-is-rejected
  (with-app "expired"
    (lambda (_file)
      (let* ((now (clock:now))
             (a (set-auction-expiry (an-auction 1 now) (- now 1))))
        (is-equal '#(error #(auction-has-ended 1))
                  (auctions:add-auction now a))))))

(deftest bid-on-a-missing-auction-is-not-found
  (with-app "missing"
    (lambda (_file)
      (let ((now (clock:now)))
        (is-equal '#(error #(auction-not-found 99))
                  (auctions:place-bid now (a-bid 99 1 now 10)))
        (is-equal '#(error #(auction-not-found 99))
                  (auctions:get 99 now))))))

(deftest seller-cannot-bid-on-own-auction
  (with-app "seller"
    (lambda (_file)
      (let ((now (clock:now)))
        (is-match `#(ok ,_) (auctions:add-auction now (an-auction 1 now)))
        (is-equal '#(error #(seller-cannot-place-bids #"seller" 1))
                  (auctions:place-bid
                   (+ now 1)
                   (make-bid auction 1 bidder (a-seller) at (+ now 1) amount 10)))))))

;; The point of putting each auction under a supervisor: a crash must not
;; reset it.
(deftest killed-auction-recovers-its-bids
  (with-app "kill"
    (lambda (_file)
      (let ((now (clock:now)))
        (auctions:add-auction now (an-auction 1 now))
        (lists:foreach
         (lambda (n) (auctions:place-bid (+ now n) (a-bid 1 n (+ now n) (* 10 n))))
         '(1 2 3))
        (is-equal 3 (length (bids-of 1 (+ now 10))))
        (let ((pid (auction-registry:whereis_name 1)))
          (erlang:exit pid 'kill)
          (wait-for-restart 1 pid 50)
          (is-not-equal pid (auction-registry:whereis_name 1))
          (is-equal 3 (length (bids-of 1 (+ now 10)))))))))

(deftest auctions-survive-an-application-restart
  (with-app "restart"
    (lambda (file)
      (let ((now (clock:now)))
        (auctions:add-auction now (an-auction 1 now))
        (auctions:add-auction now (an-auction 2 now))
        (auctions:place-bid (+ now 1) (a-bid 1 1 (+ now 1) 10))
        (application:stop 'auctions)
        (let ((`#(ok ,_) (application:ensure_all_started 'auctions)))
          (is-equal 2 (length (auctions:list-auctions)))
          (is-equal 1 (length (bids-of 1 (+ now 10))))
          (is-equal 0 (length (bids-of 2 (+ now 10))))
          (is-equal '(auction-added auction-added bid-accepted)
                    (lists:sort (log-tags file))))))))

;; A gen_server answers no calls until init returns, and init writes
;; AuctionAdded, so a bid can never be logged before its auction.
(deftest auction-added-precedes-bid-accepted-in-the-log
  (with-app "order"
    (lambda (file)
      (let ((now (clock:now)))
        (auctions:add-auction now (an-auction 1 now))
        (auctions:place-bid (+ now 1) (a-bid 1 1 (+ now 1) 10))
        (is-equal '(auction-added bid-accepted) (log-tags file))))))

;; When the store refuses the write, the bid is neither acknowledged, nor in
;; memory, nor on disk.
(deftest write-failure-is-neither-accepted-nor-logged
  (with-app "wfail" (map 'max-bytes 400)
    (lambda (file)
      (let* ((now (clock:now))
             (_ (auctions:add-auction now (an-auction 1 now)))
             (results (lists:map
                       (lambda (n)
                         (element 1 (auctions:place-bid
                                     (+ now n) (a-bid 1 n (+ now n) (* 10 n)))))
                       '(1 2 3 4 5 6))))
        (is-equal 'ok (lists:nth 1 results))
        (is-equal 'error (lists:last results))
        (let ((accepted (length (lists:filter (lambda (r) (=:= r 'ok)) results))))
          (is-equal accepted (length (bids-of 1 (+ now 100))))
          (is-equal accepted
                    (length (lists:filter (lambda (t) (=:= t 'bid-accepted))
                                          (log-tags file)))))))))

;;; -----------------
;;; helpers
;;; -----------------

(defun wait-for-restart
  ((_id _old 0) 'timeout)
  ((id old n)
   (let ((pid (auction-registry:whereis_name id)))
     (if (andalso (is_pid pid) (=/= pid old))
       'ok
       (progn (timer:sleep 20) (wait-for-restart id old (- n 1)))))))
