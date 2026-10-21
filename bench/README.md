# Benchmarks

All commands run from the repository root. The app runs in the OTP
container; `wrk` runs on the host.

```sh
./lfe.sh rebar3 compile                       # bench loads _build/default
docker run -d --name bench -u "$(id -u):$(id -g)" -e HOME=/work/.devcache \
  -e ERL_LIBS=/work/_build/default/lib -v "$PWD":/work -w /work -p 8080:8080 \
  auctions-erlang:test escript bench/boot.escript        # add `nosync' to skip fsync
bench/seed.sh http://localhost:8080 50        # 50 auctions, 3 bids each
bench/run.sh http://localhost:8080 lfe        # req/s and latency per endpoint
docker rm -f bench                            # frees 8080 for ./lfe.sh
```

`bench/micro.escript` times the parts (sync, time format, JSON) on their own:

```sh
./lfe.sh escript bench/micro.escript
```

Delete `tmp/bench-events.log` between runs, or create ids collide.
