// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentLoan} from "../src/AgentLoan.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentWrapped721} from "../src/AgentWrapped721.sol";
import {AgentReputationBadge} from "../src/AgentReputationBadge.sol";
import {DemoAgentCollection, TestUSD} from "./SepoliaDemo.s.sol";

/// A classic NFT, as any existing collection.
contract ClassicNFT is ERC721 {
    uint256 public lastId;

    constructor() ERC721("Classic NFT", "CLS") {}

    function mint(address to) external returns (uint256 id) {
        id = ++lastId;
        _mint(to, id);
    }
}

/// Shared helpers: relayed orders signed by an agent's session key.
abstract contract AgentScript is Script {
    function _agentDoes(uint256 key, AgentAccount acc, address target, bytes memory data) internal returns (bytes memory) {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = acc.execDigest(target, 0, data, acc.nonce(), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return acc.executeBySig(target, 0, data, deadline, abi.encodePacked(r, s, v));
    }

    function _sigs(uint256 x, uint256 y, bytes32 digest) internal pure returns (bytes[] memory sigs) {
        if (vm.addr(x) > vm.addr(y)) (x, y) = (y, x);
        sigs = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(x, digest);
        sigs[0] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(y, digest);
        sigs[1] = abi.encodePacked(r, s, v);
    }
}

/// Testnet, step 1 of 2: every venue on Base Sepolia, on the registry and agents deployed by
/// SepoliaDemo. Loan repaid, loan left to default, staking with rewards started, reputation badge,
/// wrapping and unwrapping a classic NFT. Step 2 (SepoliaVenuesLater) runs once time has passed.
contract SepoliaVenues is AgentScript {
    AttestedAgentRegistry constant REG = AttestedAgentRegistry(0x587b4c01Db0c4779Fb729c5f806879A5ECd6e087);
    DemoAgentCollection constant NFT = DemoAgentCollection(0xD5d6caFd31435539fE626a733b173cACe81a3fD8);
    TestUSD constant USD = TestUSD(0x498FCE178C28af9FBC6f8c529DD1b6Ae37B3A780);
    AgentAccount constant ACC1 = AgentAccount(payable(0x90c55bB78C4f13822dA7Bb6bfD6777e471602FeA));
    AgentAccount constant ACC2 = AgentAccount(payable(0xF392e59B2bFef511D1d6AA18e0eBB00948d5c70c));

    function run() external {
        uint256 deployer = vm.envUint("DEPLOYER_KEY");
        uint256 a1 = vm.envUint("ATTESTER1");
        uint256 a2 = vm.envUint("ATTESTER2");
        uint256 k1 = vm.envUint("AGENT1_KEY");
        uint256 k2 = vm.envUint("AGENT2_KEY");
        address me = vm.addr(deployer);

        vm.startBroadcast(deployer);
        AgentLoan loan = new AgentLoan();
        AgentStaking staking = new AgentStaking(IERC721(address(NFT)), IERC20(address(USD)), me, 300);
        AgentReputationBadge badges = new AgentReputationBadge(IAgentRegistry(address(REG)), 0.0001 ether, 10, 1 days);
        ClassicNFT classic = new ClassicNFT();
        AgentWrapped721 wrapper =
            new AgentWrapped721(IERC721(address(classic)), IAgentRegistry(address(REG)), true, "Agent-Only Classic", "AO-CLS");
        REG.setVenue(address(loan), true, keccak256("AgentLoan"), _sigs(a1, a2, REG.hashVenue(address(loan), true, keccak256("AgentLoan"))));
        REG.setVenue(address(staking), true, keccak256("AgentStaking"), _sigs(a1, a2, REG.hashVenue(address(staking), true, keccak256("AgentStaking"))));
        USD.mint(address(ACC1), 100e6);
        USD.mint(address(ACC2), 100e6);

        // Loan, repaid: agent 1 borrows 10 against a token and repays 11.
        uint256 t1 = abi.decode(_agentDoes(k1, ACC1, address(NFT), abi.encodeCall(NFT.mint, (keccak256("loan, repaid")))), (uint256));
        _agentDoes(k1, ACC1, address(NFT), abi.encodeCall(NFT.approve, (address(loan), t1)));
        _agentDoes(k1, ACC1, address(loan), abi.encodeCall(loan.offer, (IERC721(address(NFT)), t1, IERC20(address(USD)), 10e6, 11e6, 1 days)));
        _agentDoes(k2, ACC2, address(USD), abi.encodeCall(USD.approve, (address(loan), 10e6)));
        _agentDoes(k2, ACC2, address(loan), abi.encodeCall(loan.fund, (IERC721(address(NFT)), t1, IERC20(address(USD)), 10e6, 11e6, 1 days)));
        _agentDoes(k1, ACC1, address(USD), abi.encodeCall(USD.approve, (address(loan), 11e6)));
        _agentDoes(k1, ACC1, address(loan), abi.encodeCall(loan.repay, (IERC721(address(NFT)), t1)));
        _agentDoes(k2, ACC2, address(loan), abi.encodeCall(loan.withdraw, (IERC20(address(USD)))));

        // Loan left to default: one-minute term; agent 2 claims the token in step 2.
        uint256 t2 = abi.decode(_agentDoes(k1, ACC1, address(NFT), abi.encodeCall(NFT.mint, (keccak256("loan, defaulted")))), (uint256));
        _agentDoes(k1, ACC1, address(NFT), abi.encodeCall(NFT.approve, (address(loan), t2)));
        _agentDoes(k1, ACC1, address(loan), abi.encodeCall(loan.offer, (IERC721(address(NFT)), t2, IERC20(address(USD)), 5e6, 6e6, 60)));
        _agentDoes(k2, ACC2, address(USD), abi.encodeCall(USD.approve, (address(loan), 5e6)));
        _agentDoes(k2, ACC2, address(loan), abi.encodeCall(loan.fund, (IERC721(address(NFT)), t2, IERC20(address(USD)), 5e6, 6e6, 60)));

        // Staking: 30 tUSD streamed over 5 minutes; agent 2 stakes a token.
        USD.mint(me, 30e6);
        USD.approve(address(staking), 30e6);
        staking.notifyRewardAmount(30e6);
        uint256 t3 = abi.decode(_agentDoes(k2, ACC2, address(NFT), abi.encodeCall(NFT.mint, (keccak256("staked")))), (uint256));
        _agentDoes(k2, ACC2, address(NFT), abi.encodeCall(NFT.approve, (address(staking), t3)));
        _agentDoes(k2, ACC2, address(staking), abi.encodeCall(staking.stake, (t3)));

        // Reputation badge: an issuer offers, agent 1 claims; the badge can never move.
        badges.registerIssuer{value: 0.0001 ether}();
        uint256 offerId = badges.offer(address(ACC1), keccak256("completed-task"), keccak256("evidence #1"), "ipfs://example");
        _agentDoes(k1, ACC1, address(badges), abi.encodeCall(badges.claim, (offerId)));

        // Any classic NFT, made agent-only by wrapping, then unwrapped by its holder.
        uint256 c = classic.mint(address(ACC1));
        _agentDoes(k1, ACC1, address(classic), abi.encodeCall(classic.approve, (address(wrapper), c)));
        uint256[] memory ids = new uint256[](1);
        ids[0] = c;
        _agentDoes(k1, ACC1, address(wrapper), abi.encodeCall(wrapper.depositFor, (address(ACC1), ids)));
        require(wrapper.ownerOf(c) == address(ACC1), "not wrapped");
        _agentDoes(k1, ACC1, address(wrapper), abi.encodeCall(wrapper.withdrawTo, (address(ACC1), ids)));
        vm.stopBroadcast();

        require(NFT.ownerOf(t1) == address(ACC1), "loan not repaid");
        require(NFT.ownerOf(t2) == address(loan), "loan not funded");
        require(NFT.ownerOf(t3) == address(staking), "not staked");
        require(badges.ownerOf(offerId) == address(ACC1), "badge not claimed");
        require(classic.ownerOf(c) == address(ACC1), "not unwrapped");
        console.log("loan      ", address(loan));
        console.log("staking   ", address(staking));
        console.log("badges    ", address(badges));
        console.log("classic   ", address(classic));
        console.log("wrapper   ", address(wrapper));
        console.log("defaulted token", t2);
        console.log("staked token   ", t3);
        console.log("badge id       ", offerId);
    }
}

/// Testnet, step 2 of 2, once the loan term and the reward period have passed.
contract SepoliaVenuesLater is AgentScript {
    DemoAgentCollection constant NFT = DemoAgentCollection(0xD5d6caFd31435539fE626a733b173cACe81a3fD8);
    TestUSD constant USD = TestUSD(0x498FCE178C28af9FBC6f8c529DD1b6Ae37B3A780);
    AgentAccount constant ACC2 = AgentAccount(payable(0xF392e59B2bFef511D1d6AA18e0eBB00948d5c70c));

    function run() external {
        AgentLoan loan = AgentLoan(vm.envAddress("LOAN"));
        AgentStaking staking = AgentStaking(vm.envAddress("STAKING"));
        uint256 t2 = vm.envUint("DEFAULTED_TOKEN");
        uint256 t3 = vm.envUint("STAKED_TOKEN");
        uint256 k2 = vm.envUint("AGENT2_KEY");
        uint256 before = USD.balanceOf(address(ACC2));

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        _agentDoes(k2, ACC2, address(loan), abi.encodeCall(loan.claim, (IERC721(address(NFT)), t2)));
        _agentDoes(k2, ACC2, address(staking), abi.encodeCall(staking.unstake, (t3)));
        vm.stopBroadcast();

        require(NFT.ownerOf(t2) == address(ACC2), "default not claimed");
        require(NFT.ownerOf(t3) == address(ACC2), "not unstaked");
        console.log("rewards received (tUSD, 6 decimals)", USD.balanceOf(address(ACC2)) - before);
    }
}
