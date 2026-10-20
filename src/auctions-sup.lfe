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

(defun children () '())

(defun child (mod fun args)
  `#M(id ,mod
      start #(,mod ,fun ,args)
      restart permanent
      shutdown 2000
      type worker
      modules (,mod)))
