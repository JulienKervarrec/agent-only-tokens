"""Checks that the conformance suite catches each deliberately wrong implementation.

Runs `forge test` with the `faulty` profile (test-faulty/) and requires every faulty
implementation to fail the test that covers its missing check, and the reference
implementation (test/conformance) to pass the whole suite in the normal run.
Exit code 1 if any faulty implementation slips through.
"""
import json, os, subprocess, sys

# Each wrong implementation, and a test of the suite that must catch it.
EXPECTED = {
    "FaultyNoInterface": "test_AdvertisesTheInterfacesAndItsRegistry()",
    "FaultyAnyCaller": "test_AnOperatorThatStopsBeingRecognisedCannotBurn()",
    "FaultyAnyRecipientViaVenue": "test_EvenAVenueCannotSendToAHuman()",
    "FaultyPush": "test_AnAgentCannotPushToAnotherAgent()",
    "FaultyAnyOperator": "test_AHumanCannotBeApproved()",
    "FaultyNoClearWhenFrozen": "test_ClearingAnApprovalAlwaysWorks()",
    "FaultyAnyGranter": "test_AnUnrecognisedHolderCannotGrantAnApproval()",
    "FaultyNoHolderOnGrant": "test_AnOperatorOfAnUnrecognisedHolderCannotGrantAnApproval()",
    "FaultyFrozenMoves": "test_AnUnrecognisedHoldersTokenDoesNotMove()",
    # The ERC-1155 profile and its suite.
    "Faulty1155NoInterface": "test_AdvertisesTheInterfacesAndItsRegistry()",
    "Faulty1155AnyCaller": "test_AnOperatorThatStopsBeingRecognisedCannotBurn()",
    "Faulty1155AnyRecipientViaVenue": "test_EvenAVenueCannotSendToAHuman()",
    "Faulty1155Push": "test_AnAgentCannotPushToAnotherAgent()",
    "Faulty1155AnyOperator": "test_AHumanCannotBeApproved()",
    "Faulty1155NoClearWhenFrozen": "test_ClearingAnApprovalAlwaysWorks()",
    "Faulty1155AnyGranter": "test_AnUnrecognisedOwnerCannotGrantAnApproval()",
    "Faulty1155FrozenMoves": "test_AnUnrecognisedHoldersTokensDoNotMove()",
}

env = dict(os.environ, FOUNDRY_PROFILE="faulty")
run = subprocess.run(["forge", "test", "--json"], env=env, capture_output=True, text=True)
start = run.stdout.find("{")
if start < 0:
    sys.exit("no JSON from forge:\n" + run.stdout[-2000:] + run.stderr[-2000:])
results = json.loads(run.stdout[start:])

problems = 0
seen = set()
for suite, data in results.items():
    name = suite.split(":")[-1]
    if name not in EXPECTED:
        continue
    seen.add(name)
    failed = sorted(t for t, r in data["test_results"].items() if r["status"] != "Success")
    ok = EXPECTED[name] in failed
    problems += not ok
    print(f"{'caught' if ok else 'MISSED'}  {name}: {len(failed)} failing test(s): {', '.join(failed) or 'none'}")
for name in sorted(set(EXPECTED) - seen):
    problems += 1
    print(f"MISSING {name}: not run")
print(f"{len(EXPECTED)} faulty implementations, {problems} problem(s)")
sys.exit(1 if problems else 0)
