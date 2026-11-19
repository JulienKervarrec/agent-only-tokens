# First enclave agent, 16 November 2026

Recorded on a Phala Cloud machine (Intel TDX, dstack OS 0.5.12) for the first
agent enrolled by hardware attestation: study section 3.13, and "The run" in
`../README.md`.

- `quote.hex`: the quote of the enrollment.
- `quote-rotation.hex`: the quote after a restart, for the new key.
- `quote-modified.hex`, `modified-docker-compose.yml`, `event-digests-modified.hex`:
  a modified build of the program, and its quote, refused by the verifier.
- `rtmr3-events.txt`, `event-digests.hex`: the names and payloads of the
  events dstack measured, and their digests, as submitted.

`SHA256SUMS` lists the hash of each file (`sha256sum -c SHA256SUMS`).
