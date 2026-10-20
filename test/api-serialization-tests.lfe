;;; Port of test/ApiSerializationSpec.hs.
(defmodule api-serialization-tests
  (behaviour ltest-unit)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")

(deftest can-understand-first-auction
  (is-equal `#(ok ,(map 'id 1
                        'starts-at (sample-data:ms "2016-01-01T00:00:00.000Z")
                        'title #"First auction"
                        'ends-at (sample-data:ms "2016-02-01T00:00:00.000Z")
                        'currency 'vac
                        'typ `#(timed-ascending ,(timed-ascending:default-options))))
            (web-types:add-auction-req
             (json:decode #"{ \"id\":1,\"startsAt\":\"2016-01-01T00:00:00.000Z\",\"endsAt\":\"2016-02-01T00:00:00.000Z\",\"title\":\"First auction\" }"))))

(deftest can-understand-bid-request
  (is-equal '#(ok 10) (web-types:bid-req (json:decode #"{ \"amount\":10 }"))))
