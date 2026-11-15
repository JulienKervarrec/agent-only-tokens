// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {console} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {ERC721AgentOnly} from "../src/ERC721AgentOnly.sol";
import {AgentReputationBadge} from "../src/AgentReputationBadge.sol";
import {DemoAgentCollection} from "./SepoliaDemo.s.sol";
import {AgentScript} from "./SepoliaVenues.s.sol";

/// Testnet: the rules against the live Base Sepolia contracts. State changes (freeze, unfreeze,
/// a new agent retired) are sent on chain; each forbidden action is attempted on the chain's state
/// at that point and must fail with the expected error. Forbidden actions are not sent, since a
/// script cannot broadcast a transaction that fails.
contract SepoliaRules is AgentScript {
    AttestedAgentRegistry constant REG = AttestedAgentRegistry(0x587b4c01Db0c4779Fb729c5f806879A5ECd6e087);
    DemoAgentCollection constant NFT = DemoAgentCollection(0xD5d6caFd31435539fE626a733b173cACe81a3fD8);
    AgentReputationBadge constant BADGES = AgentReputationBadge(0xdbf8aF05A58714e205F9a260A13B10A33f11d967);
    AgentAccount constant ACC1 = AgentAccount(payable(0x90c55bB78C4f13822dA7Bb6bfD6777e471602FeA));
    AgentAccount constant ACC2 = AgentAccount(payable(0xF392e59B2bFef511D1d6AA18e0eBB00948d5c70c));
    uint256 constant T1 = 2; // held by agent 1 (loan repaid)

    uint256 checks;

    function _expect(bool failed, bytes memory err, bytes4 expected, string memory what) internal {
        bytes4 got = err.length >= 4 ? bytes4(err) : bytes4(0);
        require(failed && got == expected, what);
        checks++;
        console.log("refused as expected:", what);
    }

    /// An order signed by the agent's key, simulated on the current state; returns the failure data.
    function _try(uint256 key, AgentAccount acc, address target, bytes memory data) internal returns (bool failed, bytes memory err) {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = acc.execDigest(target, 0, data, acc.nonce(), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        try acc.executeBySig(target, 0, data, deadline, abi.encodePacked(r, s, v)) {
            failed = false;
        } catch (bytes memory e) {
            (failed, err) = (true, e);
        }
    }

    function run() external {
        uint256 deployer = vm.envUint("DEPLOYER_KEY");
        uint256 k1 = vm.envUint("AGENT1_KEY");
        uint256 a1 = vm.envUint("ATTESTER1");
        uint256 a2 = vm.envUint("ATTESTER2");
        address human = vm.addr(deployer);
        bool failed;
        bytes memory err;
        bytes4 notAgent = ERC721AgentOnly.NotAgent.selector;

        // 1. A human wallet cannot mint, nor be approved, nor receive.
        vm.prank(human);
        try NFT.mint(bytes32(0)) {} catch (bytes memory e) { (failed, err) = (true, e); }
        _expect(failed, err, notAgent, "a human wallet mints");
        (failed, err) = _try(k1, ACC1, address(NFT), abi.encodeCall(NFT.approve, (human, T1)));
        _expect(failed, err, notAgent, "an agent approves a human wallet");
        (failed, err) = _try(k1, ACC1, address(NFT), abi.encodeCall(NFT.setApprovalForAll, (human, true)));
        _expect(failed, err, notAgent, "an agent approves a human wallet as operator (a marketplace)");
        (failed, err) = _try(k1, ACC1, address(NFT), abi.encodeCall(IERC721.transferFrom, (address(ACC1), human, T1)));
        _expect(failed, err, notAgent, "an agent sends a token to a human wallet");

        // 2. No unsolicited token: an agent cannot push a token to another agent.
        (failed, err) = _try(k1, ACC1, address(NFT), abi.encodeCall(IERC721.transferFrom, (address(ACC1), address(ACC2), T1)));
        _expect(failed, err, ERC721AgentOnly.NotPulledByRecipient.selector, "an agent pushes a token to another agent");

        // 3. A badge never moves.
        (failed, err) = _try(k1, ACC1, address(BADGES), abi.encodeCall(IERC721.transferFrom, (address(ACC1), address(ACC2), 1)));
        require(failed, "a badge moved");
        checks++;
        console.log("refused as expected: a badge is transferred");

        // 4. Frozen agent: its token does not move and it cannot grant approvals.
        vm.startBroadcast(deployer);
        REG.setFrozen(1, true);
        vm.stopBroadcast();
        vm.prank(address(ACC1)); // whatever the account type, the token refuses
        try NFT.setApprovalForAll(address(ACC2), true) {} catch (bytes memory e) { (failed, err) = (true, e); }
        _expect(failed, err, notAgent, "a frozen agent grants an approval");
        (failed, err) = _try(k1, ACC1, address(NFT), abi.encodeCall(IERC721.approve, (address(ACC2), T1)));
        _expect(failed, err, AgentAccount.NotKey.selector, "the key of a frozen agent drives its account");
        vm.startBroadcast(deployer);
        REG.setFrozen(1, false);
        vm.stopBroadcast();

        // 5. A retired agent stops at once; its bond only comes back after the exit delay.
        uint256 k3 = uint256(keccak256(abi.encode("throwaway agent 3", k1)));
        bytes32 evidence = keccak256("sepolia demo agent 3");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes[] memory sigs = _sigs(a1, a2, REG.hashEnrollment(3, vm.addr(k3), evidence, human, 0, deadline));
        vm.startBroadcast(deployer);
        REG.enroll{value: REG.bond()}(3, vm.addr(k3), evidence, deadline, sigs);
        REG.retire(3);
        vm.stopBroadcast();
        require(!REG.isAgent(REG.accountOf(3)), "retired agent still active");
        vm.prank(human);
        try REG.withdrawBond(3) {} catch (bytes memory e) { (failed, err) = (true, e); }
        _expect(failed, err, AttestedAgentRegistry.TooEarly.selector, "the bond is withdrawn right after retiring");

        console.log("checks passed:", checks);
    }
}
