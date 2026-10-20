;;; Commands and events. Port of AuctionSite.Domain.Commands.
;;;
;;; Commands:  #(add-auction At Auction) | #(place-bid At Bid)
;;; Events:    #(auction-added At Auction) | #(bid-accepted At Bid)
;;;
;;; The JSON codec here serves the HTTP boundary. The event store writes these
;;; tuples to a disk_log as Erlang terms, not as JSON; see PARITY.md.
(defmodule commands
  (export
   (command-to-json 1)
   (command-from-json 1)
   (event-to-json 1)
   (event-from-json 1)
   (fold-events 1)))

(include-lib "auctions/include/auctions.lfe")

;;; ---------------
;;; json codec
;;; ---------------

(defun command-to-json
  ((`#(add-auction ,at ,a))
   (map #"$type" #"AddAuction" #"at" (clock:format at) #"auction" (auction:to-json a)))
  ((`#(place-bid ,at ,b))
   (map #"$type" #"PlaceBid" #"at" (clock:format at) #"bid" (bid:to-json b))))

(defun event-to-json
  ((`#(auction-added ,at ,a))
   (map #"$type" #"AuctionAdded" #"at" (clock:format at) #"auction" (auction:to-json a)))
  ((`#(bid-accepted ,at ,b))
   (map #"$type" #"BidAccepted" #"at" (clock:format at) #"bid" (bid:to-json b))))

(defun command-from-json (obj)
  (from-json obj #"AddAuction" 'add-auction #"PlaceBid" 'place-bid))

(defun event-from-json (obj)
  (from-json obj #"AuctionAdded" 'auction-added #"BidAccepted" 'bid-accepted))

(defun from-json
  ((obj auction-type auction-tag bid-type bid-tag) (when (is_map obj))
   (case (tuple (maps:find #"$type" obj) (maps:find #"at" obj))
     ((tuple `#(ok ,typ) `#(ok ,at-bin))
      (case (clock:parse at-bin)
        (`#(ok ,at) (payload obj typ at auction-type auction-tag bid-type bid-tag))
        (_ `#(error #(invalid-command ,obj)))))
     (_ `#(error #(invalid-command ,obj)))))
  ((other _ _ _ _)
   `#(error #(invalid-command ,other))))

(defun payload (obj typ at auction-type auction-tag bid-type bid-tag)
  (cond
   ((=:= typ auction-type)
    (case (auction:from-json (maps:get #"auction" obj (map)))
      (`#(ok ,a) `#(ok #(,auction-tag ,at ,a)))
      (_ `#(error #(invalid-command ,obj)))))
   ((=:= typ bid-type)
    (case (bid:from-json (maps:get #"bid" obj (map)))
      (`#(ok ,b) `#(ok #(,bid-tag ,at ,b)))
      (_ `#(error #(invalid-command ,obj)))))
   ('true `#(error #(unknown-command-type ,typ)))))

;;; -----------------
;;; replay
;;; -----------------

;; Fold a log back into #M(AuctionId #(Auction State)). This is the same code
;; path an auction process uses to rebuild itself after a restart.
(defun fold-events (events)
  (lists:foldl (lambda (event acc) (apply-event event acc)) (map) events))

(defun apply-event
  ((`#(auction-added ,_ ,a) auctions)
   (maps:put (auction-id a) (tuple a (auction:empty-state a)) auctions))
  ((`#(bid-accepted ,_ ,b) auctions)
   (case (maps:find (bid-auction b) auctions)
     (`#(ok #(,a ,state))
      (let ((`#(,next ,_) (auction-state:add-bid b state)))
        (maps:put (bid-auction b) (tuple a next) auctions)))
     ('error (error `#(auction-not-found ,(bid-auction b)))))))
