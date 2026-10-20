;;; Users. Port of the User type in AuctionSite.Domain.Core.
;;;
;;; #(buyer-or-seller Id Name) | #(support Id), with Id and Name binaries.
;;; The wire form is a single pipe-separated string.
(defmodule user
  (export
   (user-id 1)
   (user->binary 1)
   (binary->user 1)))

(defun user-id
  ((`#(buyer-or-seller ,id ,_)) id)
  ((`#(support ,id)) id))

(defun user->binary
  ((`#(buyer-or-seller ,id ,name))
   (erlang:iolist_to_binary (list #"BuyerOrSeller|" id #"|" name)))
  ((`#(support ,id))
   (erlang:iolist_to_binary (list #"Support|" id))))

;; Haskell splits on "|" and demands exactly three or two parts, so a name
;; containing a pipe fails to parse. Kept as-is.
(defun binary->user (bin)
  (case (binary:split bin #"|" '(global))
    ((list #"BuyerOrSeller" id name) `#(ok #(buyer-or-seller ,id ,name)))
    ((list #"Support" id) `#(ok #(support ,id)))
    (_ `#(error #(invalid-user ,bin)))))
