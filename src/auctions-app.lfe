;;; Application callback. Port of app/Main.hs.
;;; Replay completes before the HTTP listener starts.
(defmodule auctions-app
  (behaviour application)
  (export
   (start 2)
   (stop 1)))

(defun LISTENER () 'auctions-http)

(defun start (_type _args)
  (logger:set_application_level 'auctions 'all)
  (case (auctions-sup:start_link)
    (`#(ok ,pid)
     (case (start-listener)
       ('ok
        (logger:info "auctions listening on port ~p" (list (http-port)))
        `#(ok ,pid))
       (`#(error ,reason)
        `#(error ,reason))))
    (other other)))

(defun stop (_state)
  (catch (cowboy:stop_listener (LISTENER)))
  'ok)

(defun start-listener ()
  (case (cowboy:start_clear (LISTENER)
                            `(#(port ,(http-port)))
                            (map 'env (map 'dispatch (http-auctions-handler:routes))))
    (`#(ok ,_) 'ok)
    (`#(error #(already_started ,_)) 'ok)
    (`#(error ,reason) `#(error ,reason))))

(defun http-port ()
  (case (application:get_env 'auctions 'http_port)
    (`#(ok ,port) port)
    ('undefined 8080)))
