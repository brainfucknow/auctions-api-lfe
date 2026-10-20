#!/usr/bin/env bash
# Drive the running API with the curl examples from the upstream README.
# Run inside the container: ./lfe.sh bash scripts/smoke-http.sh
set -uo pipefail
cd /work
rm -f tmp/smoke-events.log
cat > /tmp/boot.escript <<'EOF'
#!/usr/bin/env escript
main(_) ->
    application:load(auctions),
    application:set_env(auctions, events_file, "tmp/smoke-events.log"),
    application:set_env(auctions, http_port, 8080),
    {ok, _} = application:ensure_all_started(auctions),
    timer:sleep(60000).
EOF
escript /tmp/boot.escript & BOOT=$!
for i in $(seq 1 50); do curl -s -o /dev/null http://localhost:8080/auctions && break; sleep 0.2; done

SELLER='eyJzdWIiOiJhMSIsICJuYW1lIjoiVGVzdCIsICJ1X3R5cCI6IjAifQo='
BUYER='eyJzdWIiOiJhMiIsICJuYW1lIjoiQnV5ZXIiLCAidV90eXAiOiIwIn0K='

show() { printf '%-28s %s\n' "$1" "$2"; }

show "GET /auctions (empty)" "$(curl -s -w ' [%{http_code}]' http://localhost:8080/auctions)"

show "POST /auctions no auth" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions \
  -H 'Content-Type: application/json' -d '{"id":1,"startsAt":"2023-01-01T10:00:00.000Z","endsAt":"2033-12-31T10:00:00.000Z","title":"First auction"}')"

show "POST /auctions" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions \
  -H 'Content-Type: application/json' -H "x-jwt-payload: $SELLER" \
  -d '{"id":1,"startsAt":"2023-01-01T10:00:00.000Z","endsAt":"2033-12-31T10:00:00.000Z","title":"First auction"}')"

show "POST /auctions dup" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions \
  -H 'Content-Type: application/json' -H "x-jwt-payload: $SELLER" \
  -d '{"id":1,"startsAt":"2023-01-01T10:00:00.000Z","endsAt":"2033-12-31T10:00:00.000Z","title":"First auction"}')"

show "POST bid (stray '=')" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions/1/bids \
  -H 'Content-Type: application/json' -H "x-jwt-payload: $BUYER" -d '{"amount":100}')"

show "POST bid too low" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions/1/bids \
  -H 'Content-Type: application/json' -H "x-jwt-payload: $BUYER" -d '{"amount":50}')"

show "POST bid by seller" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions/1/bids \
  -H 'Content-Type: application/json' -H "x-jwt-payload: $SELLER" -d '{"amount":500}')"

show "POST bid missing auction" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions/99/bids \
  -H 'Content-Type: application/json' -H "x-jwt-payload: $BUYER" -d '{"amount":100}')"

show "POST bid bad body" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions/1/bids \
  -H 'Content-Type: application/json' -H "x-jwt-payload: $BUYER" -d 'not json')"

show "POST bad hdr + bad body" "$(curl -s -w ' [%{http_code}]' -X POST http://localhost:8080/auctions/1/bids \
  -H 'Content-Type: application/json' -H 'x-jwt-payload: garbage' -d 'not json')"

show "GET /auctions/1" "$(curl -s -w ' [%{http_code}]' http://localhost:8080/auctions/1)"
show "GET /auctions" "$(curl -s -w ' [%{http_code}]' http://localhost:8080/auctions)"
show "GET /auctions/99" "$(curl -s -w ' [%{http_code}]' http://localhost:8080/auctions/99)"

kill $BOOT 2>/dev/null
wait $BOOT 2>/dev/null
