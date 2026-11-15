# Real dstack quote and event log

`quote.hex` (a real Intel TDX quote, version 4, 5,006 bytes) and
`rtmr3-events.hex` (the 48-byte digests of its eight RTMR3 events, in order)
are taken unchanged from the test suite of
[Dstack-TEE/dstack](https://github.com/Dstack-TEE/dstack), commit
`b936f86f4136487fc44d26dc0d29181d37b25994`, file
`dstack/verifier/fixtures/quote-report.json` (fields `quote` and the `imr: 3`
entries of `event_log`). That repository is under the Apache License 2.0,
reproduced in `LICENSE`.

The events are, in order: `system-preparing`, `app-id`, `compose-hash`
(payload `3763bc34552cf3a27ff71ad5f7a90471562a1a2df552dfc1998cba2d60da27e7`),
`instance-id`, `boot-mr-done`, `key-provider`, `system-ready`, and one event
written by the application. All use the V1 digest format. Replaying them gives
the quote's RTMR3; `../DstackEnrollment.t.sol` checks it.

The quote's report data is `0x1234` followed by zeros. The tests use the quote
as it is, and also with its report data or its RTMR3 overwritten, which a real
DCAP verifier would reject: as in `../tdx`, a stand-in replaces that verifier.

keccak256 of the quote: `0xbd3ec656e37a3d0226d98673e24119f383edb69ffaf0442b4796835f3f70e148`.
