;;; Time: the clock the domain is given, plus the ISO 8601 codec.
;;;
;;; Domain time is integer milliseconds since the Unix epoch.
;;;
;;; The wire format follows Aeson: trailing zeros are trimmed from the
;;; fractional part and the decimal point is dropped when nothing is left, so
;;; a whole second prints as 2018-08-04T00:00:00Z rather than ...00.000Z.
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
  (trim-fraction
   (list_to_binary
    (calendar:system_time_to_rfc3339 ms '(#(unit millisecond) #(offset "Z"))))))

(defun parse (iso)
  (try
    `#(ok ,(calendar:rfc3339_to_system_time iso '(#(unit millisecond))))
    (catch ((tuple _ _ _) `#(error #(invalid-timestamp ,iso))))))

;;; -----------------
;;; private functions
;;; -----------------

(defun trim-fraction (bin)
  (case (binary:split bin #".")
    ((list head rest)
     (let ((trimmed (strip-zeros (binary:part rest 0 (- (byte_size rest) 1)))))
       (if (=:= trimmed #"")
         (erlang:iolist_to_binary (list head #"Z"))
         (erlang:iolist_to_binary (list head #"." trimmed #"Z")))))
    (_ bin)))

(defun strip-zeros (bin)
  (let ((n (byte_size bin)))
    (if (andalso (> n 0) (=:= (binary:part bin (- n 1) 1) #"0"))
      (strip-zeros (binary:part bin 0 (- n 1)))
      bin)))
