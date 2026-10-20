;;; Domain errors. Port of the Errors type in AuctionSite.Domain.Core.
;;;
;;; Note the JSON discriminator here is "type", not the "$type" used by
;;; commands and events.
(defmodule errors
  (export (to-json 1)))

(defun to-json
  ((`#(auction-not-found ,a))
   (map #"type" #"AuctionNotFound" #"auctionId" a))
  ((`#(auction-already-exists ,a))
   (map #"type" #"AuctionAlreadyExists" #"auctionId" a))
  ((`#(auction-has-ended ,a))
   (map #"type" #"AuctionHasEnded" #"auctionId" a))
  ((`#(auction-has-not-started ,a))
   (map #"type" #"AuctionHasNotStarted" #"auctionId" a))
  ((`#(seller-cannot-place-bids ,u ,a))
   (map #"type" #"SellerCannotPlaceBids" #"userId" u #"auctionId" a))
  ((`#(invalid-user-data ,u))
   (map #"type" #"InvalidUserData" #"user" u))
  ((`#(must-place-bid-over-highest-bid ,a))
   (map #"type" #"MustPlaceBidOverHighestBid" #"amount" a))
  (('already-placed-bid)
   (map #"type" #"AlreadyPlacedBid")))
