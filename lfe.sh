#!/usr/bin/env bash
# Run a command inside the OTP 28 container with the repo mounted.
# Usage: ./lfe.sh rebar3 lfe ltest     |     ./lfe.sh bash -lc '...'
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec docker run --rm $(test -t 0 && echo -it) \
  -u "$(id -u):$(id -g)" \
  -e HOME=/work/.devcache \
  -e ERL_LIBS=/work/_build/default/lib \
  -v "$ROOT":/work -w /work \
  -p 8080:8080 \
  auctions-erlang:test "$@"
