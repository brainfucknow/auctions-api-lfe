;;; Shared record definitions.
;;;
;;; All times are integer milliseconds since the Unix epoch; see PARITY.md for
;;; why this port uses millisecond rather than Haskell's picosecond resolution.

(defrecord auction
  id          ; integer
  starts-at   ; ms since epoch
  title       ; binary
  expiry      ; ms since epoch, the *initial* expiry
  seller      ; user tuple
  typ         ; #(timed-ascending Opts) | #(single-sealed-bid Opts)
  currency)   ; vac | sek | dkk

(defrecord bid
  auction     ; auction id
  bidder      ; user tuple
  at          ; ms since epoch
  amount)     ; integer
