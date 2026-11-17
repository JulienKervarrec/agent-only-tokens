# Two hardware makers: the checks behind section 3.24

Step 1.8 of the plan asked whether an enrollment could demand proofs from two
chip makers. This folder holds what we ran to answer it, with no cloud account:
real attestations already published by others, checked twice, once in Python and
once on chain (Foundry, Osaka rules, Base's per-transaction gas cap).

| What | Sample | Off chain (Python `cryptography`) | On chain (Foundry) |
| --- | --- | --- | --- |
| AWS Nitro Enclaves document | `test/data/nitro-sample.bin`, a real document of 3 January 2026, from the tests of [base/nitro-validator](https://github.com/base/nitro-validator) (MIT) | Chain to the AWS root (fingerprint `64:1A:03:21…BB:5B`, as [published by AWS](https://docs.aws.amazon.com/enclaves/latest/user/verify-root.html)) and document signature: valid | `NitroCheck.t.sol`, with that project's reviewed verifier: 13.3 million gas per document once the chain is cached; first time 6 calls, 39.4 million gas in all, none above 13.3 million |
| AMD SEV-SNP report (Milan) | `test/data/amd/`: report and VCEK from the tests of [virtee/sev](https://github.com/virtee/sev) (Apache-2.0); ARK and ASK as shipped there, the ARK identical to Automata's copy | ARK → ASK → VCEK (RSA-4096 PSS) and the report signature (P-384): valid | `AmdCheck.t.sol`: each RSA-4096 certificate check about 5.0 to 5.4 million gas (our own PSS code, `RsaPss4096`, unreviewed); the report signature 5.0 million gas with the Nitro project's P-384 verifier |

Each check also refuses a document changed by one bit; the Nitro one refuses a
certificate past its end (a Nitro leaf certificate lives three hours).

To run: `sh setup.sh` (brings the Nitro verifier at commit `0ea0d12`), then
`forge test`; `python3 scripts/check_nitro.py test/data/nitro-sample.bin` and
`python3 scripts/check_snp.py test/data/amd`. `extract_snp.py` made the `.bin`
inputs of `AmdCheck` from the AMD files.

Not done here: parsing the AMD certificates on chain (only their signatures are
checked) and the AMD revocation list; a Nitro or AMD machine of our own.
