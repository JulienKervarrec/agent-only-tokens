# The ERC proposal

`erc-agent-only-tokens.md` is the proposal, written in the format of the
[ethereum/ERCs](https://github.com/ethereum/ERCs) repository (step 4.3 of the
plan). Nothing has been submitted: that is step 4.6, and the decision to make
the project public is Julien's.

To build the files to submit:

    python3 tools/erc_package.py OUT --check

It writes `OUT/ERCS/erc-TBD.md` and `OUT/assets/erc-TBD/`, the conformance
suite made self-contained, and runs the reference implementation exactly as
printed in the proposal through that suite in a fresh project. The automatic
checks run it on every change.

Before submitting, fill in:

- `eip`: the number the editors assign (also in the file names and the links);
- `author`: the authors' names and GitHub handles;
- `discussions-to`: the Ethereum Magicians topic opened for it;

then run the repository's own checks (`eipw`) on the file.
