;;; Top-level supervisor.
;;;
;;; Phase 3 wires the real tree here as `rest_for_one' in the order
;;; event-store, auction-registry, auction-sup, event-replayer: the ETS event
;;; index lives inside event-store, so if that process dies everything started
;;; after it must be restarted and rebuilt from the log rather than left holding
;;; references to a store that forgot them.
(defmodule auctions-sup
  (behaviour supervisor)
  ;; supervisor implementation
  (export
   (start_link 0)
   (stop 0))
  ;; callback implementation
  (export
    (init 1)))

;;; ----------------
;;; config functions
;;; ----------------

(defun SERVER () (MODULE))
(defun supervisor-opts () '())
(defun sup-flags ()
  `#M(strategy rest_for_one
      intensity 3
      period 60))

;;; -------------------------
;;; supervisor implementation
;;; -------------------------

(defun start_link ()
  (supervisor:start_link `#(local ,(SERVER))
                         (MODULE)
                         (supervisor-opts)))

(defun stop ()
  (case (erlang:whereis (SERVER))
    ('undefined 'ok)
    (pid (exit pid 'normal) 'ok)))

;;; -----------------------
;;; callback implementation
;;; -----------------------

(defun init (_args)
  `#(ok #(,(sup-flags) ,(children))))

;;; -----------------
;;; private functions
;;; -----------------

;; Order matters. The event store owns the ETS index, so if it dies the index
;; dies with it and everything after it must be rebuilt from the file rather
;; than left pointing at a store that forgot them. The replayer runs last,
;; once the store, the registry and the auction supervisor are all up.
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
