#!/usr/bin/env bash
# seed.sh HOST N  -- create auctions 1..N with 3 bids each
set -u
HOST=$1; N=$2
SELLER='eyJzdWIiOiJhMSIsICJuYW1lIjoiVGVzdCIsICJ1X3R5cCI6IjAifQo='
BUYER='eyJzdWIiOiJhMiIsICJuYW1lIjoiQnV5ZXIiLCAidV90eXAiOiIwIn0K'
for i in $(seq 1 $N); do
  curl -s -o /dev/null -X POST $HOST/auctions -H 'Content-Type: application/json' -H "x-jwt-payload: $SELLER" \
    -d "{\"id\":$i,\"startsAt\":\"2023-01-01T10:00:00.000Z\",\"endsAt\":\"2033-12-31T10:00:00.000Z\",\"title\":\"Auction $i\",\"currency\":\"VAC\"}"
  for a in 10 20 30; do
    curl -s -o /dev/null -X POST $HOST/auctions/$i/bids -H 'Content-Type: application/json' -H "x-jwt-payload: $BUYER" -d "{\"amount\":$a}"
  done
done
