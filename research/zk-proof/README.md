# A real zero-knowledge proof of our quote (step 2.2)

A RISC Zero Groth16 proof that Automata's DCAP program (release 1.1, image id
`0xcc80dc6c1c1f8bc524101b72b3900301dc87887457c8fcaf552e45e2a02b9695`) checked
our own dstack quote (`test/experimental/phala/quote-own-prelaunch.hex`)
against the Intel data on Base Sepolia. The result is in `test/fork/zk/`
(`risc0-seal.hex`, `risc0-journal.hex`) and is checked by
`test/fork/ZkRealProofBaseSepolia.t.sol`. Study, section 3.27.

## Files

| File | What it does |
| --- | --- |
| `src/main.rs` | Builds the program's input (quote, Intel data, time of check), then `exec` (runs it, no proof) or `prove` (Groth16). Refuses to prove unless the image id and the verifier selector (`73c457ba`, RISC Zero v3.0.0 on Base Sepolia) match |
| `fetch_collateral.py` | Reads the Intel data on chain through Automata's PCCS router (read-only calls, standard library only) |
| `setup.sh` | Fetches Automata's code at the release commit and our quote, each checked by hash, and the Intel data |
| `phala/run.sh` | The same steps, then the proof, on a rented Phala machine; serves the result over HTTP |
| `phala/make_compose.py` | Writes the `docker-compose.yml` for that machine, our sources inside |
| `phala/patch_dcap.py` | Lets Automata's `dcap-rs` build outside its workspace |

No key, no wallet: the inputs are public, the output is a public proof.

## Run

```sh
sh setup.sh
cargo build --release
./target/release/aot-zkp exec quote.hex col out      # seconds: out/journal.hex
./target/release/aot-zkp prove quote.hex col out     # x86 + Docker; out/seal.hex too
```

`exec` runs on any machine. `prove` needs an x86 machine with Docker (RISC Zero
runs its Groth16 prover image), about 15 GB of memory, and network access to
RISC Zero's files outside crates.io. The versions in Automata's lock file
matter: the newest RISC Zero crates give the selector `e71e6620`, which no
verifier on Base Sepolia accepts.

## What was done, 17 November 2026

- `exec` in our cloud workspace: 13.4 million cycles, under a second; output
  byte for byte equal to Automata's direct on-chain check of the same quote.
- `prove` on a Phala machine, 8 cores and 16 GB, $0.464 an hour: build 21
  minutes, proof 82.5 minutes, $0.86 in all, machine deleted afterwards. On the
  machine, `RISC0_WORK_DIR=aotwork` (a relative path) makes Docker mount the
  named volume `aotwork`, shared with the prover container through the
  machine's Docker socket.
- Output recomputed in the workspace with the same time of check: identical.
  Proof accepted by a read-only call to the RISC Zero router of Base Sepolia.
