;;; Cowboy handler for the four routes. Port of AuctionSite.Web.App.
;;;
;;; | GET  /auctions           | no auth | list items                       |
;;; | GET  /auctions/:id       | no auth | item + bids, winner, winnerPrice |
;;; | POST /auctions           | auth    | the AuctionAdded event           |
;;; | POST /auctions/:id/bids  | auth    | the BidAccepted event            |
;;;
;;; Unlike Haskell, the auth header is decoded before the body is read, so a
;;; caller that sends both a bad header and a bad body gets 401 rather than
;;; 400. See PARITY.md.
(defmodule http-auctions-handler
  (behaviour cowboy_handler)
  (export
   (init 2)
   (routes 0)))

(include-lib "auctions/include/auctions.lfe")

(defun routes ()
  (cowboy_router:compile
   (list (tuple '_
                (list (tuple "/auctions" (MODULE) 'auctions)
                      (tuple "/auctions/:id" (MODULE) 'auction)
                      (tuple "/auctions/:id/bids" (MODULE) 'bids))))))

(defun init (req route)
  (tuple 'ok (dispatch route (cowboy_req:method req) req) route))

;;; routing

(defun dispatch
  (('auctions #"GET" req) (list-auctions req))
  (('auctions #"POST" req) (create-auction req))
  (('auction #"GET" req) (with-id req (lambda (id r) (show-auction id r))))
  (('bids #"POST" req) (with-id req (lambda (id r) (place-bid id r))))
  ((_ _ req) (text 405 #"Method Not Allowed" req)))

;; Spock's typed `var' simply fails to route a non-integer id, so there is no
;; auction id to report; a bare 404 is the closest equivalent.
(defun with-id (req f)
  (case (to-integer (cowboy_req:binding 'id req))
    (`#(ok ,id) (funcall f id req))
    ('error (text 404 #"Not Found" req))))

;;; handlers

(defun list-auctions (req)
  (json 200
        (lists:map (lambda (a) (web-types:auction-list-item a))
                   (auctions:list-auctions))
        req))

(defun show-auction (id req)
  (case (auctions:get id (clock:now))
    (`#(ok #(,a ,state)) (json 200 (web-types:auction-detail a state) req))
    (`#(error ,e) (json 404 (errors:to-json e) req))))

(defun create-auction (req)
  (authenticated req
    (lambda (seller obj r)
      (case (web-types:add-auction-req obj)
        (`#(error ,_) (bad-request r))
        (`#(ok ,spec)
         (let ((now (clock:now)))
           (reply-event (auctions:add-auction now (auction-of spec seller)) r)))))))

(defun place-bid (id req)
  (authenticated req
    (lambda (bidder obj r)
      (case (web-types:bid-req obj)
        (`#(error ,_) (bad-request r))
        (`#(ok ,amount)
         (let ((now (clock:now)))
           (reply-event
            (auctions:place-bid now (make-bid auction id
                                              bidder bidder
                                              at now
                                              amount amount))
            r)))))))

(defun auction-of (spec seller)
  (make-auction id (maps:get 'id spec)
                starts-at (maps:get 'starts-at spec)
                title (maps:get 'title spec)
                expiry (maps:get 'ends-at spec)
                seller seller
                typ (maps:get 'typ spec)
                currency (maps:get 'currency spec)))

;;; plumbing

(defun authenticated (req f)
  (case (jwt:decode-user (cowboy_req:header #"x-jwt-payload" req #""))
    ('error (text 401 #"Unauthorized" req))
    (`#(ok ,user)
     (case (read-json req)
       (`#(error ,r) (bad-request r))
       (`#(ok ,obj ,r) (funcall f user obj r))))))

(defun read-json (req)
  (case (cowboy_req:read_body req)
    (`#(ok ,body ,r)
     (try
       (case (json:decode body)
         (obj (when (is_map obj)) `#(ok ,obj ,r))
         (_ `#(error ,r)))
       (catch ((tuple _ _ _) `#(error ,r)))))
    (`#(more ,_ ,r) `#(error ,r))))

(defun reply-event (result req)
  (case result
    (`#(ok ,event) (json 200 (commands:event-to-json event) req))
    ('#(error event-store-unavailable) (unavailable req))
    (`#(error #(auction-not-found ,id))
     (json 404 (errors:to-json `#(auction-not-found ,id)) req))
    (`#(error ,e) (json 400 (errors:to-json e) req))))

(defun bad-request (req)
  (json 400 (web-types:api-error #"could not parse request body") req))

(defun unavailable (req)
  (json 503 (web-types:api-error #"event store unavailable") req))

(defun json (status body req)
  (cowboy_req:reply status
                    (map #"content-type" #"application/json; charset=utf-8")
                    (json:encode body)
                    req))

(defun text (status body req)
  (cowboy_req:reply status
                    (map #"content-type" #"text/plain; charset=utf-8")
                    body
                    req))

(defun to-integer (bin)
  (try
    `#(ok ,(binary_to_integer bin))
    (catch ((tuple _ _ _) 'error))))
