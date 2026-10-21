;;; Shared EUnit tests ported from test/AuctionStateSpecs.hs `incrementSpec'.
(defmodule increment-spec
  (export (tests 1)))

(include-lib "ltest/include/ltest-macros.lfe")

(defun tests (base)
  (let ((starts-at (sample-data:starts-at))
        (ends-at (sample-data:ends-at)))
    (list
     (tuple "can increment twice"
            (lambda ()
              (let* ((s (auction-state:inc (sample-data:bid-time) base))
                     (s2 (auction-state:inc (sample-data:bid-time) s)))
                (is-equal s s2))))
     (tuple "wont end just after start"
            (lambda ()
              (is-equal 'false
                        (auction-state:has-ended
                         (auction-state:inc (+ starts-at 1) base)))))
     (tuple "wont end just before end"
            (lambda ()
              (is-equal 'false
                        (auction-state:has-ended
                         (auction-state:inc (- ends-at 1) base)))))
     (tuple "wont end just before start"
            (lambda ()
              (is-equal 'false
                        (auction-state:has-ended
                         (auction-state:inc (- starts-at 1) base)))))
     (tuple "will have ended just after end"
            (lambda ()
              (is-equal 'true
                        (auction-state:has-ended
                         (auction-state:inc (+ ends-at 1) base)))))
     (tuple "will end at exactly the end time"
            (lambda ()
              (is-equal 'true
                        (auction-state:has-ended
                         (auction-state:inc ends-at base)))))
     (tuple "wont end at exactly the start time"
            (lambda ()
              (is-equal 'false
                        (auction-state:has-ended
                         (auction-state:inc starts-at base))))))))
