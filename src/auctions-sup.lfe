;;; Top-level supervisor.
(defmodule auctions-sup
  (behaviour supervisor)
  (export
   (start_link 0)
   (stop 0))
  (export
    (init 1)))

(defun SERVER () (MODULE))
(defun supervisor-opts () '())
(defun sup-flags ()
  `#M(strategy rest_for_one
      intensity 3
      period 60))

(defun start_link ()
  (supervisor:start_link `#(local ,(SERVER))
                         (MODULE)
                         (supervisor-opts)))

(defun stop ()
  (case (erlang:whereis (SERVER))
    ('undefined 'ok)
    (pid (exit pid 'normal) 'ok)))

(defun init (_args)
  `#(ok #(,(sup-flags) ,(children))))

;; rest_for_one rebuilds dependent processes when their ETS owner dies.
;; Replay runs last, after the store, registry and auction supervisor are ready.
(defun children ()
  (list (worker 'event-store 'permanent)
        (worker 'auction-registry 'permanent)
        (supervisor-child 'auction-sup)
        (worker 'event-replayer 'transient)))

(defun worker (mod restart)
  `#M(id ,mod
      start #(,mod start_link ())
      restart ,restart
      shutdown 5000
      type worker
      modules (,mod)))

(defun supervisor-child (mod)
  `#M(id ,mod
      start #(,mod start_link ())
      restart permanent
      shutdown infinity
      type supervisor
      modules (,mod)))
