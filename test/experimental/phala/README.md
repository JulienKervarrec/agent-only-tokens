# Real quotes from production dstack machines

Four Intel TDX quotes (version 4, 5,010 bytes each) produced on 16 November 2026
on Phala Cloud (dstack OS 0.5.12): three by one machine running the program of
`examples/enclave-agent`, with the digests of its ten RTMR3 events, and one by
another machine running the second program (`examples/enclave-agent/v2`).
They are our own runs; the full record is in `examples/enclave-agent`.

| File | What it is |
| --- | --- |
| `quote.hex` | First enrollment. Compose hash `95b3c3e5…dc21` |
| `quote-rotation.hex` | Same build after a restart: another key, same measurements |
| `quote-modified.hex` | A modified build on the same machine. Compose hash `6b79fe24…1412` |
| `event-digests.hex` | The 48-byte digests of the RTMR3 events of the first two quotes |
| `quote-other-machine.hex` | The second program on another machine. Compose hash `580353bb…7ef8`; same attributes, MRTD and RTMR0 to RTMR2 as the first three |

Automata's DCAP verifier accepted all four on Base Sepolia, platform level 0.
In the local tests a stand-in replaces it, as in `../tdx`; `../../fork` runs the
first, the third and the fourth through the real one.

All four were produced by the production image of dstack OS 0.5.12 exactly as dstack
published it: `tools/dstack_image.py` recomputes their MRTD, RTMR1 and RTMR2 from
`dstack-0.5.12.tar.gz` (study, section 3.20).
