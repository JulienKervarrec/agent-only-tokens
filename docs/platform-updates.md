# When the hardware's security level changes

Procedure for a registry whose agents are enrolled by Intel TDX attestation
(`src/experimental`). Written on 17 November 2026 from what Base Sepolia holds
that day; study, section 3.23.

## What decides that a machine is up to date

Our verifiers ask Automata's DCAP verifier to check each quote. Its answer
carries a platform level, computed from data that Intel signs and that is
stored on chain. Each verifier accepts the levels fixed at its deployment
(`acceptedTcb`; ours: up to date only). The registry never reads the level: it
asks the verifier when a key is enrolled or rotated, and then trusts that key
until it expires (`keyTtl`, 30 days in our deployments).

Three facts follow, read on Base Sepolia on 17 November 2026:

- **Intel's data on chain expires.** The list of Intel's TCB recoveries for TDX
  was issued on 31 October and expires on 30 November 2026 at 20:29 UTC; the
  data for the platform of our Phala machines (FMSPC `20a06f000000`) expires
  on 15 December. After the first date Automata's verifier refuses every quote
  (`TcbEvalExpiredOrNotFound`), however up to date the machine, until newer data
  is published. Automata publishes it; the data contracts accept updates only
  through Automata's dashboard.
- **"Up to date" is measured against Intel's "standard" data.** That is TCB
  evaluation 20 (recovery of 12 August 2025). Intel has published two later
  recoveries, 21 (10 February 2026) and 22 (11 August 2026). The data for them
  is not on chain for our platform, so a verifier cannot demand them today.
- **A machine whose platform falls behind keeps its current key.** The
  registry does not ask again. The key works until it expires; the machine
  cannot obtain a new one.

## Who watches what

| What | Who | How | When |
| --- | --- | --- | --- |
| Expiry of Intel's data on chain, and the recoveries a verifier can demand | Anyone; the nightly workflow of this repository | `python3 tools/collateral.py`: the real verifier is asked, at simulated future dates, until which day it accepts each archived quote. Fails when one would be refused within 3 days | Every night |
| Intel's security advisories and TCB recoveries | The attesters | Intel's advisories page; the list printed by the tool | When published |
| The provider's update of its machines | The sponsor of each agent | The provider's announcements; the level returned for a new quote | After each recovery |

## What to do

**The data on chain is about to expire** (the tool fails, or fewer than 3
days are left). Nothing breaks at once: enrolled keys keep working. Ask
Automata to publish the new data (their dashboard, or their support): this is
a contact outside the project. Avoid key rotations until it is done. If it is
not done before keys expire, agents stop acting until it is; their accounts and
tokens are kept.

**Intel publishes a recovery.** Within a day, the attesters read the advisory
and choose one of three answers.

1. **The flaw lets the host read a machine's memory** (as TEE.fail did): keys
   may have leaked. The attesters halt enrollments at once
   (`haltEnrollments`, no notice delay) and revoke the agents of the affected
   platforms if their keys may be known (`revoke`, final: the bond is
   forfeited). Each sponsor can freeze its own agent at once and lift it
   later (`setFrozen`). Enrollments resume under a verifier announced
   afterwards.
2. **The flaw is serious but not urgent**: nothing to do on chain. Once the
   data of the recovery is on chain and the provider has updated its
   machines, the attesters announce a verifier that demands that evaluation
   (`setEnrollmentVerifier`, effective after the notice delay). Today
   Automata's verifier can be asked for a given evaluation, but our verifiers
   always ask for the standard one: demanding a later evaluation means adding
   that parameter to the verifier first.
3. **The provider is late and agents must keep running**: the attesters can
   announce a verifier that also accepts "out of date" (level 4), for a time
   they state, then announce the strict one again. Each change waits for the
   notice delay, so holders see it coming.

**A machine is refused with `PlatformNotAccepted`.** Its sponsor waits for the
provider's update, or moves the agent to an updated machine of the same build:
the code identity is the same, so the new machine obtains a key for the same
account.

## Tested

- `test/experimental/DstackConfigId.t.sol`: a platform that falls out of date
  keeps its key until expiry and gets a new one once updated; the sponsor's
  freeze is immediate; a verifier accepting "out of date" takes effect only
  after the notice delay and still refuses other levels; a halt stops
  everything at once.
- `test/fork/AutomataBaseSepolia.t.sol`, on a copy of Base Sepolia: a real
  quote from a machine that is out of date for Intel is refused by a verifier
  that accepts up-to-date platforms only; a real quote from our Phala machine
  is accepted today and refused 45 days later, when Intel's data on chain has
  expired.

## Not done

- No quote was refused for a recovery published after our machines started:
  Intel's later data is not on chain to try.
- The timings above are those of 17 November 2026. The tool prints the
  current ones.
