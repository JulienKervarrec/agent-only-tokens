# The ERC proposal

`erc-agent-only-tokens.md` is the proposal, written in the format of the
[ethereum/ERCs](https://github.com/ethereum/ERCs) repository (step 4.3 of the
plan). Nothing has been submitted: that is step 4.6, and the decision to make
the project public is Julien's.

**Status after the review of 23 November 2026.** The proposal was written
before that review and still speaks of "agents". The review concluded that the
registry shows which program holds a key, not that an AI does
([`../paper.md`](../paper.md), section 2), and that the part most worth
proposing may be the pull rule alone. The proposal is kept here as written; it
would be renamed and reduced before any submission.

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
