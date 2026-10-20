;;; Time: the clock the domain is given, plus the ISO 8601 codec.
;;;
;;; Domain time is integer milliseconds since the Unix epoch. The wire format
;;; is ISO 8601 UTC with exactly three fractional digits, which is what
;;; calendar/2 emits for the millisecond unit.
;;;
;;; `now' reads a fixed value from the application environment when one is set,
;;; which is how the HTTP tests pin the clock.
(defmodule clock
  (export
   (now 0)
   (format 1)
   (parse 1)))

(defun now ()
  (case (application:get_env 'auctions 'fixed_time)
    (`#(ok ,ms) ms)
    ('undefined (erlang:system_time 'millisecond))))

(defun format (ms)
  (list_to_binary
   (calendar:system_time_to_rfc3339 ms '(#(unit millisecond) #(offset "Z")))))

(defun parse (iso)
  (try
    `#(ok ,(calendar:rfc3339_to_system_time iso '(#(unit millisecond))))
    (catch ((tuple _ _ _) `#(error #(invalid-timestamp ,iso))))))
