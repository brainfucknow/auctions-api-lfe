# auctions-lfe

A Lisp Flavoured Erlang / OTP port of
[auctions-api-haskell](https://github.com/wallymathieu/auctions-api-haskell),
with one supervised process per auction and a `disk_log` event store.

Parity is measured against upstream commit `6caa4853`; see [PARITY.md](PARITY.md)
for the pin and the complete list of intentional deviations.

## Building and testing

There is no local Erlang install; everything runs in an OTP 28 container via a
thin wrapper (OTP 27+ is required for the built-in `json` module).

```sh
./lfe.sh rebar3 compile
./lfe.sh rebar3 as test lfe ltest                  # unit tests
./lfe.sh rebar3 as test lfe ltest --test-type=all  # unit + system tests
./lfe.sh rebar3 lfe repl              # REPL
./scripts/fetch-upstream.sh           # clone the pinned Haskell source
./lfe.sh bash scripts/smoke-http.sh   # drive the API with the README's curl calls
```

## Running the release

```sh
docker build -t auctions-lfe:0.1.0 .
docker run -p 8080:8080 -v auctions-data:/var/lib/auctions auctions-lfe:0.1.0
```

The event log lives at `/var/lib/auctions/events.log` inside the container, so
mount a volume there to keep auctions across restarts. Port and path are set in
[config/sys.config](config/sys.config).

## Layout

| Path | Contents |
| --- | --- |
| `include/auctions.lfe` | the `auction` and `bid` records |
| `src/` | domain modules and OTP plumbing |
| `test/` | ltest twins of the Haskell Hspec suite |
| `test/samples/` | fixtures copied verbatim from upstream |
| `scripts/` | dev helpers (upstream fetch, HTTP smoke) |
| `config/` | `sys.config` and `vm.args` for the release |

## Phase status

| Phase | State |
| --- | --- |
| 0. Scaffold | done — app starts with an empty tree |
| 1. Pure domain | done — 48 ltest cases, 1:1 with the four Hspec state specs |
| 2. Serialization | done — JSON codecs, ISO 8601 clock, 13 ported cases |
| 3. OTP skeleton | done — process per auction, disk_log store, 9 system tests |
| 4. HTTP | done — four cowboy routes, 10 ported ApiSpec cases |
| 5. Packaging | done — relx release, Docker image, CI |
| 6. OTP extras | done — `gen_statem` variant, hibernation, PropEr invariants |

## The gen_statem variant

`auction-server` (a `gen_server`) backs an auction by default. Phase 6 adds
`auction-statem`, which additionally ends an auction on a `state_timeout` and
hibernates it afterwards:

```erlang
%% sys.config
{auctions, [{auction_module, 'auction-statem'}]}
```

It emits an extra `AuctionEnded` event; see [PARITY.md](PARITY.md). Its timer
is armed off the real clock, so it is tested separately from the parity suite,
which pins the clock.

## Gotchas

Things that cost time here, recorded so they only cost it once.

- **`defrecord` generates zero-arity field-index functions.** `(defrecord auction
  id ...)` defines `(auction-id)` returning `2`, the tuple index of `id`, as well
  as the `(auction-id Record)` accessor. A same-named helper in the including
  module is silently shadowed at call sites, so records quietly get an index
  where a value was meant. Avoid `<record>-<field>` names for your own functions.
- **`ltest` can run stale beams.** The first `rebar3 as test lfe ltest` after an
  edit may report results from the previous build. Re-run, or compile first.
- **LFE compiles behaviours without checking callbacks**, so a typo in
  `handle_call` surfaces at runtime, not compile time.
- **`json:decode` returns maps with binary keys** — look them up with `#"..."`
  literals, never atoms.
- **Hyphenated module names are atoms.** Quote them in `rebar.config`,
  `sys.config` and relx: `'auctions-sup'`.
- **`rebar3_proper` only discovers properties in `.erl` files**, so it cannot
  see an LFE property module. The properties here are driven through
  `proper:quickcheck/2` from ltest instead.
- **A `gen_statem` reply action does not re-hibernate.** Answering a call wakes
  an ended auction up for good unless `hibernate` is added to every reply.
- **`ltest` only runs unit suites by default.** Pass `--test-type=all` to
  include `ltest-system` modules, or they silently do not run.
- **`call` is an LFE core form** (used for dynamic dispatch, as in
  `auction-state`). Defining your own `call/3` fails to compile.
- **`is_process_alive` is not guard-safe** — test it in the body, not a `when`.
- **Keep `inc` lazy.** Reading an auction must not persist the advanced state,
  or the English timing tests diverge.
