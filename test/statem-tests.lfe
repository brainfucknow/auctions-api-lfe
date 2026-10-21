;;; System tests for auction-statem.
;;; Use real time so domain expiry checks agree with the timers.
(defmodule statem-tests
  (behaviour ltest-system)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")
(include-lib "auctions/include/auctions.lfe")

(defun a-seller () #(buyer-or-seller #"seller" #"Seller"))
(defun a-buyer () #(buyer-or-seller #"b1" #"Buyer"))

(defun an-auction (now expiry time-frame)
  (make-auction id 1
                starts-at (- now 1000)
                title #"Soon"
                expiry expiry
                seller (a-seller)
                typ `#(timed-ascending ,(map 'reserve-price 0
                                             'min-raise 0
                                             'time-frame time-frame))
                currency 'sek))

(defun ended? (id)
  (let ((`#(ok #(,_a ,state)) (auctions:get id (clock:now))))
    (auction-state:has-ended state)))

(defun winner (id)
  (let ((`#(ok #(,_a ,state)) (auctions:get id (clock:now))))
    (auction-state:try-get-amount-and-winner state)))

(defun current-function (pid)
  (element 2 (erlang:process_info pid 'current_function)))

;; How a hibernating process reports its current function depends on the OTP
;; release: 27 shows erlang:hibernate/3, 28 shows gen_statem:loop_hibernate/3.
;; Both mean the process has hibernated.
(defun hibernating? (pid)
  (lists:member (current-function pid)
                '(#(erlang hibernate 3) #(gen_statem loop_hibernate 3))))

;; No reader has to poke the auction for it to lapse; the timer does it.
(deftest auction-ends-on-its-own-timer
  (with-statem
   (lambda (_file)
     (let ((now (clock:now)))
       (auctions:add-auction now (an-auction now (+ now 300) 0))
       (auctions:place-bid (+ now 1) (make-bid auction 1 bidder (a-buyer)
                                               at (+ now 1) amount 42))
       (is-equal 'false (ended? 1))
       (timer:sleep 700)
       (is-equal 'true (ended? 1))
       (is-equal `#(some 42 #"b1") (winner 1))))))

(deftest auction-ended-is-written-to-the-log
  (with-statem
   (lambda (file)
     (let ((now (clock:now)))
       (auctions:add-auction now (an-auction now (+ now 300) 0))
       (timer:sleep 700)
       (is-equal '(auction-added auction-ended) (log-tags file))))))

;; Replay must not record the same ending twice.
(deftest auction-ended-is-not-republished-after-a-restart
  (with-statem
   (lambda (file)
     (let ((now (clock:now)))
       (auctions:add-auction now (an-auction now (+ now 300) 0))
       (timer:sleep 700)
       (application:stop 'auctions)
       (let ((`#(ok ,_) (application:ensure_all_started 'auctions)))
         (timer:sleep 300)
         (is-equal '(auction-added auction-ended) (log-tags file)))))))

(deftest ended-auction-hibernates-and-stays-hibernated
  (with-statem
   (lambda (_file)
     (let ((now (clock:now)))
       (auctions:add-auction now (an-auction now (+ now 300) 0))
       (let ((pid (auction-registry:whereis_name 1)))
         (timer:sleep 700)
         (is-equal 'true (hibernating? pid))
         ;; a read wakes it; it must go back to sleep rather than stay up
         (ended? 1)
         (timer:sleep 100)
         (is-equal 'true (hibernating? pid)))))))

;; A bid inside the time frame pushes expiry out, and the timer follows it.
(deftest a-bid-in-the-time-frame-extends-the-timer
  (with-statem
   (lambda (_file)
     (let ((now (clock:now)))
       (auctions:add-auction now (an-auction now (+ now 300) 1000))
       (auctions:place-bid (+ now 1) (make-bid auction 1 bidder (a-buyer)
                                               at (+ now 1) amount 42))
       (timer:sleep 600)
       (is-equal 'false (ended? 1))
       (timer:sleep 900)
       (is-equal 'true (ended? 1))))))

(deftest statem-rejects-a-bid-after-the-auction-ended
  (with-statem
   (lambda (_file)
     (let ((now (clock:now)))
       (auctions:add-auction now (an-auction now (+ now 300) 0))
       (timer:sleep 700)
       (is-equal '#(error #(auction-has-ended 1))
                 (auctions:place-bid (clock:now)
                                     (make-bid auction 1 bidder (a-buyer)
                                               at (clock:now) amount 99)))))))

(defun with-statem (f)
  (let ((file "tmp/statem-events.log"))
    (catch (application:stop 'auctions))
    (catch (application:unload 'auctions))
    (filelib:ensure_dir file)
    (file:delete file)
    (catch (application:load 'auctions))
    (application:set_env 'auctions 'events_file file)
    (application:set_env 'auctions 'auction_module 'auction-statem)
    (application:unset_env 'auctions 'events_max_bytes)
    (application:unset_env 'auctions 'fixed_time)
    (let ((`#(ok ,_) (application:ensure_all_started 'auctions)))
      (try
        (funcall f file)
        (after
         (catch (application:stop 'auctions))
         (catch (application:unload 'auctions)))))))

(defun log-tags (file)
  (let ((`#(ok ,_) (disk_log:open `(#(name statem-inspect)
                                    #(file ,file)
                                    #(mode read_only)))))
    (let ((tags (case (disk_log:chunk 'statem-inspect 'start)
                  ('eof '())
                  (`#(,_cont ,terms) (lists:map (lambda (t) (element 1 t)) terms)))))
      (disk_log:close 'statem-inspect)
      tags)))
