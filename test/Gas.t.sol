// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentReputationBadge} from "../src/AgentReputationBadge.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";

contract PlainNft is ERC721 {
    constructor() ERC721("Plain", "PLN") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

/// The gas table of the README, as a test. Run it with:
///   forge test --isolate --match-contract GasTest
/// Each measure is then the full cost of one transaction and is written to
/// `snapshots/Gas.json`; with FORGE_SNAPSHOT_CHECK=true the run fails if a measure differs from
/// the file. Without `--isolate` the same steps run as an ordinary test and nothing is written.
contract GasTest is AgentOnlyBase {
    AgentStaking staking;
    AgentReputationBadge badges;
    address constant DISTRIBUTOR = address(0xD15);
    address constant ISSUER = address(0xB07);
    bool isolated;
    string constant PR = "https://github.com/org/repo/pull/1";

    function setUp() public override {
        super.setUp();
        // With `--isolate` every call of a test is its own transaction and pays the 21,000 gas
        // of one; otherwise a call to an empty address costs a few thousand.
        (bool ok,) = address(0xE0).call("");
        isolated = ok && vm.lastCallGas().gasTotalUsed >= 21_000;
        staking = new AgentStaking(nft, usdc, DISTRIBUTOR, 7 days);
        _venue(address(staking));
        badges = new AgentReputationBadge(IAgentRegistry(address(reg)), 0.05 ether, 3, 30 days);
        vm.deal(ISSUER, 1 ether);
        vm.prank(ISSUER);
        badges.registerIssuer{value: 0.05 ether}();
        usdc.mint(DISTRIBUTOR, 7_000 ether);
        vm.prank(DISTRIBUTOR);
        usdc.approve(address(staking), type(uint256).max);
    }

    function _measure(string memory name) private {
        if (isolated) vm.snapshotGasLastCall("Gas", name);
    }

    function test_GasTransfers() public {
        PlainNft plain = new PlainNft();
        plain.mint(address(0xA11CE), 1);
        vm.prank(address(0xA11CE));
        plain.approve(address(0xB0B), 1);
        vm.prank(address(0xB0B)); // same pattern as below: the approved recipient pulls
        plain.transferFrom(address(0xA11CE), address(0xB0B), 1);
        _measure("01 plain ERC-721 transferFrom");

        uint256 id = _mint(K1, acc1);
        _measure("04 mint, through the account");
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(acc2), id)));
        _measure("14 approval, through the account");
        vm.prank(address(acc2));
        nft.transferFrom(address(acc1), address(acc2), id);
        _measure("02 agent-only transferFrom, direct");

        _do(K2, acc2, address(nft), abi.encodeCall(nft.approve, (address(acc1), id)));
        _do(K1, acc1, address(nft), abi.encodeCall(nft.transferFrom, (address(acc2), address(acc1), id)));
        _measure("03 agent-only transferFrom, through the account");
    }

    function test_GasSale() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (nft, id, usdc, 300, address(0))));
        _measure("05 list for sale");
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(swap), 300)));
        _do(K2, acc2, address(swap), abi.encodeCall(swap.buy, (nft, id, usdc, 300)));
        _measure("06 buy");
    }

    function test_GasEnrollment() public {
        address sponsor = address(0x103);
        vm.deal(sponsor, 1 ether);
        _enroll(reg, sponsor, 3, address(0x3333), BOND);
        _measure("07 first enrollment");
        _enroll(reg, sponsor, 3, address(0x4444), 0);
        _measure("08 key rotation");

        // Once a verifier announced by the attesters has taken over (here "attesters sign",
        // announced again), every enrollment reads one more storage slot, for good.
        bytes32 why = keccak256("review");
        reg.setEnrollmentVerifier(address(0), why, FAR, _attest(A1, A2, reg.hashVerifier(address(0), why, FAR)));
        skip(NOTICE);
        _enroll(reg, sponsor, 3, address(0x5555), 0);
        _measure("15 key rotation after an announced verifier took over");

        address[] memory next = new address[](3);
        (next[0], next[1], next[2]) = (vm.addr(0xB1), vm.addr(0xB2), vm.addr(0xB3));
        bytes32 digest = reg.hashAttesters(next, 2, why, FAR);
        reg.setAttesters(next, 2, why, FAR, _attest(A1, A2, digest), _attest(0xB1, 0xB2, digest));
        _measure("16 attesters hand over to a set of three");
    }

    function test_GasBadge() public {
        vm.prank(ISSUER);
        uint256 offerId = badges.offer(address(acc1), keccak256("code-contribution"), keccak256(bytes(PR)), PR);
        _measure("09 badge offer");
        _do(K1, acc1, address(badges), abi.encodeCall(badges.claim, (offerId)));
        _measure("10 badge claim, through the account");
    }

    function test_GasStaking() public {
        uint256 id = _mint(K1, acc1);
        _do(K1, acc1, address(nft), abi.encodeCall(nft.approve, (address(staking), id)));
        _do(K1, acc1, address(staking), abi.encodeCall(staking.stake, (id)));
        _measure("11 stake, through the account");
        vm.prank(DISTRIBUTOR);
        staking.notifyRewardAmount(7_000 ether);
        skip(1 days);
        _do(K1, acc1, address(staking), abi.encodeCall(staking.getReward, ()));
        _measure("12 claim staking rewards");
        skip(1 days);
        _do(K1, acc1, address(staking), abi.encodeCall(staking.unstake, (id)));
        _measure("13 unstake with rewards");
    }
}
