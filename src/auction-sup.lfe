;;; Supervisor for per-auction processes.
;;; Restart arguments include the auction record for a fresh create;
;;; recovery uses logged events instead.
(defmodule auction-sup
  (behaviour supervisor)
  (export
   (start_link 0))
  (export
   (init 1))
  ;; supervisor API
  (export
   (start-auction 3)))

(defun SERVER () (MODULE))

(defun start_link ()
  (supervisor:start_link `#(local ,(SERVER)) (MODULE) '()))

(defun start-auction (id a at)
  (supervisor:start_child (SERVER) (list id a at)))

;; Choose the auction implementation once at supervisor startup.
(defun auction-module ()
  (case (application:get_env 'auctions 'auction_module)
    (`#(ok ,mod) mod)
    ('undefined 'auction-server)))

(defun init (_args)
  (let ((mod (auction-module)))
    `#(ok #(#M(strategy simple_one_for_one
               intensity 5
               period 60)
            (#M(id auction-server
                start #(,mod start_link ())
                restart transient
                shutdown 5000
                type worker
                modules (,mod)))))))
