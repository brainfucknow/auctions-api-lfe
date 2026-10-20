;;; Decode the x-jwt-payload header. Port of AuctionSite.Web.Jwt.
;;;
;;; The header is a base64-encoded JSON object, not a signed JWT; the app is
;;; meant to sit behind a front proxy that has already validated the token.
(defmodule jwt
  (export (decode-user 1)))

;; Lenient base64: the upstream README's own example header carries a stray
;; "=", which base64:decode rejects even with padding disabled, so padding
;; characters are stripped before decoding. See PARITY.md.
(defun decode-user (header)
  (case (payload header)
    (`#(ok ,obj) (to-user obj))
    ('error 'error)))

(defun payload (header)
  (try
    (let ((decoded (base64:decode (binary:replace header #"=" #"" '(global))
                                  (map 'padding 'false))))
      (case (json:decode decoded)
        (obj (when (is_map obj)) `#(ok ,obj))
        (_ 'error)))
    (catch ((tuple _ _ _) 'error))))

;; u_typ "0" is a buyer or seller and requires a name; "1" is support and does
;; not. Anything else fails, as in Haskell's createJwtUser.
(defun to-user (obj)
  (case (list (maps:find #"sub" obj)
              (maps:find #"name" obj)
              (maps:find #"u_typ" obj))
    ((list `#(ok ,sub) `#(ok ,name) `#(ok #"0"))
     `#(ok #(buyer-or-seller ,sub ,name)))
    ((list `#(ok ,sub) _ `#(ok #"1"))
     `#(ok #(support ,sub)))
    (_ 'error)))
