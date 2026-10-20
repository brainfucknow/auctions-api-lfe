# Parity contract

This port tracks [auctions-api-haskell](https://github.com/wallymathieu/auctions-api-haskell)
at commit [`6caa4853`](https://github.com/wallymathieu/auctions-api-haskell/tree/6caa4853f489356360a28d76885c4bd4c52faf7c)
(2026-05-05). `scripts/fetch-upstream.sh` clones that exact commit into
`.devcache/upstream` (gitignored); the Haskell test suite there is the spec.

If upstream moves, bump the pin deliberately and diff `test/` rather than
chasing master mid-port.

## Compatibility exceptions

Everything not in this table is meant to match the Haskell app exactly,
including its quirks. Anything discovered during the port that belongs here
goes here, not in a code comment.

| Behaviour | Haskell | Port | Why |
| --- | --- | --- | --- |
| Auth vs body on POST | Parses body first, so malformed JSON gives 400 before a missing header gives 401 | Decodes `x-jwt-payload` first, so 401 wins | No point validating a body for a caller not allowed to send one. Visible only to clients sending both a bad header and a bad body. |
| Event durability | `TBQueue` + async worker; reply precedes the write | `append` writes and syncs before the state changes and the reply is sent | An acknowledged bid survives a crash. Costs latency per write. |
| Store failure | Not surfaced to the client; worker crash loses queued events | 503 with `{"message":"event store unavailable"}` on write failure or timeout | New status code. Success bodies and codes unchanged. |
| Event log format | `tmp/events.jsonl`, one JSON array of events per line | `disk_log` halt log, internal format, Erlang terms | The two builds cannot share a log. JSON codecs are kept for HTTP only. |
| Base64 padding in header | Strict | Lenient (`#{padding => false}`) | The upstream README's own example has a stray `=`; strict decoding rejects the project's documentation. |
| Process restart | No equivalent; one `TVar`, one process | A crashed auction rebuilds from the log in `init` | Needed so OTP restarts do not reset an auction. |

## Wire-format rules

Checked by the serialization tests:

- User as a string: `"BuyerOrSeller|a1|Test"` or `"Support|s1"`.
- Auction type as a string: `"English|<reserve>|<minRaise>|<timeFrameSeconds>"`, `"Blind"`, `"Vickrey"`.
- Currency as `"VAC"`, `"SEK"`, `"DKK"`; amounts are plain integers.
- Timestamps ISO 8601 UTC with milliseconds: `2023-01-01T10:00:00.000Z`.
- Events and commands carry a `"$type"` discriminator.
- The auction's seller serializes under the key `user`, not `seller`.
- Create requests read `endsAt` and optional `typ`, but a stored auction
  serializes with `expiry` and `type`.
- Bid objects in `sample-commands.jsonl` carry an extra `id` the decoder ignores.
