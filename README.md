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
./lfe.sh rebar3 as test lfe ltest     # unit tests
./lfe.sh rebar3 lfe repl              # REPL
./scripts/fetch-upstream.sh           # clone the pinned Haskell source
```

## Layout

| Path | Contents |
| --- | --- |
| `include/auctions.lfe` | the `auction` and `bid` records |
| `src/` | domain modules and OTP plumbing |
| `test/` | ltest twins of the Haskell Hspec suite |
| `test/samples/` | fixtures copied verbatim from upstream |
| `scripts/` | dev helpers (upstream fetch, smoke check) |

## Phase status

| Phase | State |
| --- | --- |
| 0. Scaffold | done — app starts with an empty tree |
| 1. Pure domain | done — 48 ltest cases, 1:1 with the four Hspec state specs |
| 2. Serialization | not started |
| 3. OTP skeleton | not started |
| 4. HTTP | not started |
| 5. Packaging | not started |
| 6. OTP extras | optional |

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
- **Keep `inc` lazy.** Reading an auction must not persist the advanced state,
  or the English timing tests diverge.
