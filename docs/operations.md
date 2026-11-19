# Operating a registry: watching, incidents, keys

Step 6.6 of the plan. Who does what when something goes wrong with an
`AttestedAgentRegistry` and the agents, venues and allowances around it. Every
procedure below was rehearsed on a local chain by
[`examples/operations/drill.sh`](../examples/operations/drill.sh), which also
runs in the automatic checks.

Test network only. Before any real value, phase 6 of the plan (audit) comes
first.

## Who can act, and how fast

| Action | Who | Signatures | Takes effect |
| --- | --- | --- | --- |
| Freeze or unfreeze an agent | its sponsor | none (one transaction) | at once |
| Close an allowance and take the rest back | its sponsor | none | at once |
| Revoke an agent, for good | the attesters | threshold | at once |
| Remove a venue | the attesters | threshold | at once |
| Halt enrollments (also cancels an announced verifier) | the attesters | threshold | at once |
| Approve a venue, replace the verifier, replace the attesters | the attesters | threshold | after the notice delay |

Everything that narrows takes effect at once; everything that widens waits
for the notice delay, visible to all in the meantime.

## Watching

- **The monitor page** ([`docs/monitor`](monitor/index.html)) shows, for a
  registry, every decision announced and when it takes effect, its agents and
  its venues. Open it at least once per notice delay.
- **The events to watch**: `EnrollmentVerifierSet`, `VenueSet` and
  `AttestersSet` (something widens after the delay), `EnrollmentsHalted`,
  `Revoked`, `FrozenSet`.
- **The nightly checks** (`nightly.yml`) compare the code at every recorded
  address with the deployments file, and run the tests against Base Sepolia.
- **Intel's security level**: see the procedure of study section 3.23.

## Incidents

**1. An agent misbehaves, or its key may be known.** Its sponsor freezes it:
one transaction, no signature. It stops being an agent at once; its tokens
stop moving, even through an approval or a listing left behind. Then, if it
has an allowance, the sponsor closes it and takes the rest back: the agent can
lose at most what it had already drawn. If the agent cannot be trusted again,
the attesters revoke it: unfreezing then does not bring it back.

**2. A venue is faulty.** The attesters remove it, at once. Tokens it holds in
escrow stay there: whoever controls the venue's own functions decides what
happens to them. Before approving a venue, review its code and make sure it
cannot change.

**3. The verifier accepts too much, or a verifier was announced by mistake.**
The attesters halt enrollments, at once: no new enrollment passes, and an
announced verifier that has not taken effect is cancelled. Agents already
enrolled through the faulty verifier are revoked one by one. A correct
verifier is then announced, and enrollments resume when it takes effect.

**4. An attester key is lost or may be known.** The other attesters announce a
new set without it. It takes effect after the notice delay, as long as they
still reach the threshold. Meanwhile watch the announcements: a decision
signed with the lost key still needs the threshold.

**5. The holders of a quorum of attester keys turn hostile.** Their widening
decisions are visible for the whole notice delay: sponsors can close their
allowances, and everyone can stop relying on the registry, before anything
takes effect. Tokens cannot leave the registry's agents: a token's registry
never changes. Nothing on chain stops a quorum; choose the attesters and the
delay accordingly.

## Attester keys

- An attester is a key or a contract (a Safe, for instance, section 3.19).
  Prefer contracts with several owners for anything that holds value.
- Create keys on a dedicated device or a hardware wallet, never on a computer
  used for anything else, and never in a repository. Record only the public
  addresses, in the deployments file.
- Choose the threshold so that losing one key never leaves fewer keys than
  the threshold, and so that one stolen key never reaches it.
- Choose the notice delay so that someone will look at the monitor within it.
- Each signature has a deadline: sign with a short one.

## The drill

`bash examples/operations/drill.sh` (after `forge build`) runs, on a local
chain with throwaway keys made at run time: an agent that holds a token
approved to a venue in force and draws from its allowance; then incidents 1
to 3 above, with each effect checked on chain: frozen in one transaction, it
can no longer act and the venue can no longer take its token (checked against
a control taken before the freeze); its allowance closed, the rest back; the
venue removed at once; a verifier announced, then cancelled by a halt, after
which no enrollment passes.
