(defmodule auctions-app
  (behaviour application)
  ;; app implementation
  (export
   (start 2)
   (stop 1)))

;;; --------------------------
;;; application implementation
;;; --------------------------

(defun start (_type _args)
  (logger:set_application_level 'auctions 'all)
  (logger:info "Starting auctions application ...")
  (auctions-sup:start_link))

(defun stop (_state)
  (auctions-sup:stop)
  'ok)
