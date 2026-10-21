#!/usr/bin/env bash
# run.sh HOST LABEL  -- wrk each endpoint, print req/s and p50/p99
set -u
HOST=$1; LABEL=$2; D=${DUR:-10s}; C=${CONC:-32}; T=${THREADS:-2}
one() { # name url [lua]
  local name=$1 url=$2 lua=${3:-}
  local out
  if [ -n "$lua" ]; then out=$(wrk -t$T -c$C -d$D --latency -s "$lua" "$HOST$url" 2>&1)
  else out=$(wrk -t$T -c$C -d$D --latency "$HOST$url" 2>&1); fi
  local rps=$(echo "$out" | awk '/Requests\/sec/ {print $2}')
  local p50=$(echo "$out" | awk '$1=="50%" {print $2}')
  local p99=$(echo "$out" | awk '$1=="99%" {print $2}')
  local err=$(echo "$out" | awk '/Non-2xx/ {print $NF}')
  printf '%-8s %-22s %10s req/s  p50 %8s  p99 %8s  non2xx %s\n' "$LABEL" "$name" "$rps" "$p50" "$p99" "${err:-0}"
}
one "GET /auctions" /auctions
one "GET /auctions/1" /auctions/1
one "POST /auctions" /auctions bench/create.lua
BID_BASE=$(date +%s) one "POST bid (50 auctions)" /auctions/1/bids bench/bid.lua
