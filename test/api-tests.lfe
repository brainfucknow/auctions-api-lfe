;;; Port of test/ApiSpec.hs: drives the real cowboy listener over HTTP with
;;; the clock pinned through the application environment.
(defmodule api-tests
  (behaviour ltest-system)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")

(defun PORT () 8099)

(defun seller1 () "eyJzdWIiOiJhMSIsICJuYW1lIjoiVGVzdCIsICJ1X3R5cCI6IjAifQo=")
(defun buyer1 ()  "eyJzdWIiOiJhMiIsICJuYW1lIjoiQnV5ZXIiLCAidV90eXAiOiIwIn0K")

(defun fixed-now () "2018-08-04T00:00:00.000Z")
(defun early-time () "2018-07-01T00:00:00.000Z")
(defun late-time ()  "2018-07-16T00:00:00.000Z")

(defun first-auction-req ()
  #"{\"id\":1,\"startsAt\":\"2018-01-01T10:00:00.000Z\",\"endsAt\":\"2019-01-01T10:00:00.000Z\",\"title\":\"First auction\", \"currency\":\"VAC\" }")

(defun ended-auction-req ()
  #"{\"id\":1,\"startsAt\":\"2017-01-01T10:00:00.000Z\",\"endsAt\":\"2018-01-01T10:00:00.000Z\",\"title\":\"Ended auction\", \"currency\":\"VAC\" }")

(defun ending-soon-req ()
  #"{\"id\":1,\"startsAt\":\"2017-01-01T00:00:00.000Z\",\"endsAt\":\"2018-07-15T00:00:00.000Z\",\"title\":\"Ending Soon\",\"currency\":\"VAC\"}")

;;; -----------------
;;; expected bodies
;;; -----------------

(defun auction-fields ()
  (map #"currency" #"VAC"
       #"expiry" #"2019-01-01T10:00:00Z"
       #"id" 1
       #"startsAt" #"2018-01-01T10:00:00Z"
       #"title" #"First auction"))

(defun auction-added ()
  (map #"$type" #"AuctionAdded"
       #"at" #"2018-08-04T00:00:00Z"
       #"auction" (map #"id" 1
                       #"startsAt" #"2018-01-01T10:00:00Z"
                       #"title" #"First auction"
                       #"expiry" #"2019-01-01T10:00:00Z"
                       #"user" #"BuyerOrSeller|a1|Test"
                       #"type" #"English|0|0|0"
                       #"currency" #"VAC")))

(defun bid-accepted ()
  (map #"$type" #"BidAccepted"
       #"at" #"2018-08-04T00:00:00Z"
       #"bid" (map #"auction" 1
                   #"user" #"BuyerOrSeller|a2|Buyer"
                   #"amount" 11
                   #"at" #"2018-08-04T00:00:00Z")))

(defun with-bid ()
  (maps:merge (auction-fields)
              (map #"bids" (list (map #"amount" 11
                                      #"bidder" #"BuyerOrSeller|a2|Buyer"))
                   #"winner" 'null
                   #"winnerPrice" 'null)))

(defun without-bid ()
  (maps:merge (auction-fields)
              (map #"bids" '() #"winner" 'null #"winnerPrice" 'null)))

(defun ended-auction ()
  (map #"id" 1
       #"startsAt" #"2017-01-01T00:00:00Z"
       #"title" #"Ending Soon"
       #"expiry" #"2018-07-15T00:00:00Z"
       #"currency" #"VAC"
       #"bids" (list (map #"amount" 42 #"bidder" #"BuyerOrSeller|a2|Buyer"))
       #"winner" #"a2"
       #"winnerPrice" 42))

;;; -----------------
;;; tests
;;; -----------------

(deftest possible-to-add-auction
  (with-api (lambda () (is-equal `#(200 ,(auction-added)) (add-auction)))))

(deftest not-possible-to-add-same-auction-twice
  (with-api
   (lambda ()
     (add-auction)
     (is-equal `#(400 ,(map #"type" #"AuctionAlreadyExists" #"auctionId" 1))
               (post "/auctions" (seller1) (first-auction-req))))))

(deftest returns-added-auction
  (with-api
   (lambda ()
     (add-auction)
     (is-equal `#(200 ,(without-bid)) (get-json "/auctions/1")))))

(deftest returns-added-auctions
  (with-api
   (lambda ()
     (add-auction)
     (is-equal `#(200 ,(list (auction-fields))) (get-json "/auctions")))))

(deftest cannot-add-auction-that-has-already-ended
  (with-api
   (lambda ()
     (is-equal `#(400 ,(map #"type" #"AuctionHasEnded" #"auctionId" 1))
               (post "/auctions" (seller1) (ended-auction-req))))))

(deftest possible-to-add-bid-to-auction
  (with-api
   (lambda ()
     (add-auction)
     (is-equal `#(200 ,(bid-accepted)) (add-bid)))))

(deftest possible-to-see-the-added-bids
  (with-api
   (lambda ()
     (add-auction)
     (add-bid)
     (is-equal `#(200 ,(with-bid)) (get-json "/auctions/1")))))

(deftest not-possible-to-add-bid-to-non-existant-auction
  (with-api
   (lambda ()
     (is-equal `#(404 ,(map #"type" #"AuctionNotFound" #"auctionId" 2))
               (post "/auctions/2/bids" (buyer1) #"{\"amount\":10}")))))

(deftest missing-auth-header-is-unauthorized
  (with-api
   (lambda ()
     (is-equal '#(401 #"Unauthorized")
               (post-raw "/auctions" '() (first-auction-req))))))

;; The clock moves past expiry between the bid and the read, so the same
;; auction now discloses a winner.
(deftest reflects-ended-state-with-winner-and-price-after-expiry
  (with-api (early-time)
   (lambda ()
     (is-equal 200 (element 1 (post "/auctions" (seller1) (ending-soon-req))))
     (is-equal 200 (element 1 (post "/auctions/1/bids" (buyer1) #"{\"amount\":42}")))
     (set-now (late-time))
     (is-equal `#(200 ,(ended-auction)) (get-json "/auctions/1")))))

;;; -----------------
;;; helpers
;;; -----------------

(defun add-auction () (post "/auctions" (seller1) (first-auction-req)))
(defun add-bid () (post "/auctions/1/bids" (buyer1) #"{\"amount\":11}"))

(defun with-api (f) (with-api (fixed-now) f))

(defun with-api (now f)
  (let ((file "tmp/api-events.log"))
    (catch (application:stop 'auctions))
    (catch (application:unload 'auctions))
    (filelib:ensure_dir file)
    (file:delete file)
    (catch (application:load 'auctions))
    (application:set_env 'auctions 'events_file file)
    (application:set_env 'auctions 'http_port (PORT))
    (set-now now)
    (application:ensure_all_started 'inets)
    (let ((`#(ok ,_) (application:ensure_all_started 'auctions)))
      (try
        (funcall f)
        (after
         (catch (application:stop 'auctions))
         (catch (application:unload 'auctions)))))))

(defun set-now (iso)
  (let ((`#(ok ,ms) (clock:parse iso)))
    (application:set_env 'auctions 'fixed_time ms)))

(defun url (path) (++ "http://localhost:" (integer_to_list (PORT)) path))

(defun get-json (path)
  (decode (request 'get (tuple (url path) '()))))

(defun post (path jwt body)
  (decode (post-raw path (list (tuple "x-jwt-payload" jwt)) body)))

(defun post-raw (path headers body)
  (request 'post (tuple (url path) headers "application/json" body)))

(defun request (method req)
  (let ((`#(ok #(#(,_v ,status ,_r) ,_h ,body))
         (httpc:request method req '() '(#(body_format binary)))))
    (tuple status body)))

(defun decode
  ((`#(,status ,body)) (tuple status (json:decode body))))
