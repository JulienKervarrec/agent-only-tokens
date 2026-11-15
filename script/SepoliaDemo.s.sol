// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {ERC721AgentOnly} from "../src/ERC721AgentOnly.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentSwap} from "../src/AgentSwap.sol";

/// A collection on the standard: anything, here a content hash per token.
contract DemoAgentCollection is ERC721AgentOnly {
    uint256 public lastId;
    mapping(uint256 => bytes32) public contentHash;

    constructor(IAgentRegistry r) ERC721("Agent-Only Demo", "AOD") ERC721AgentOnly(r) {}

    function mint(bytes32 content) external returns (uint256 id) {
        id = ++lastId;
        contentHash[id] = content;
        _mint(msg.sender, id);
    }
}

/// A test stablecoin with no value, minted freely.
contract TestUSD is ERC20 {
    constructor() ERC20("Test USD (no value)", "tUSD") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Testnet demonstration. Every key is a throwaway test key passed by environment variable.
/// One relayer (the deployer) sends every transaction: the agents' session keys only sign,
/// so the agents hold no ETH.
///
///   1. deploy registry, collection, sale venue, test stablecoin
///   2. attesters approve the venue; two agents are enrolled (2 of 3 attester signatures)
///   3. agent 1 mints, approves the venue and lists the token; agent 2 buys it
contract SepoliaDemo is Script {
    uint256 constant BOND = 0.0001 ether;
    uint256 constant PRICE = 25e6; // 25 tUSD

    uint256 a1;
    uint256 a2;
    uint256 a3;
    address[] attesters;

    function _sorted2(bytes32 digest) internal view returns (bytes[] memory sigs) {
        (uint256 x, uint256 y) = vm.addr(a1) < vm.addr(a2) ? (a1, a2) : (a2, a1);
        sigs = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(x, digest);
        sigs[0] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(y, digest);
        sigs[1] = abi.encodePacked(r, s, v);
    }

    /// The agent's session key signs an order; the relayer submits it.
    function _agentDoes(uint256 key, AgentAccount acc, address target, bytes memory data) internal returns (bytes memory) {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = acc.execDigest(target, 0, data, acc.nonce(), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return acc.executeBySig(target, 0, data, deadline, abi.encodePacked(r, s, v));
    }

    function _enroll(AttestedAgentRegistry reg, uint256 id, address key, address sponsor) internal returns (AgentAccount) {
        bytes32 evidence = keccak256(abi.encode("sepolia demo agent", id));
        bytes[] memory sigs = _sorted2(reg.hashEnrollment(id, key, evidence, sponsor, 0, uint64(block.timestamp + 1 hours)));
        reg.enroll{value: BOND}(id, key, evidence, uint64(block.timestamp + 1 hours), sigs);
        return AgentAccount(payable(reg.accountOf(id)));
    }

    function run() external {
        uint256 deployer = vm.envUint("DEPLOYER_KEY");
        a1 = vm.envUint("ATTESTER1");
        a2 = vm.envUint("ATTESTER2");
        a3 = vm.envUint("ATTESTER3");
        uint256 k1 = vm.envUint("AGENT1_KEY");
        uint256 k2 = vm.envUint("AGENT2_KEY");
        address me = vm.addr(deployer);

        address[] memory att = new address[](3);
        att[0] = vm.addr(a1);
        att[1] = vm.addr(a2);
        att[2] = vm.addr(a3);
        // Strictly increasing order is only needed for signatures; the list itself is a set.

        vm.startBroadcast(deployer);
        AttestedAgentRegistry reg = new AttestedAgentRegistry(att, 2, BOND, 30 days, IERC721(address(0)), address(0));
        DemoAgentCollection nft = new DemoAgentCollection(IAgentRegistry(address(reg)));
        AgentSwap swap = new AgentSwap();
        TestUSD usd = new TestUSD();

        reg.setVenue(address(swap), true, keccak256("AgentSwap"), _sorted2(reg.hashVenue(address(swap), true, keccak256("AgentSwap"))));
        AgentAccount acc1 = _enroll(reg, 1, vm.addr(k1), me);
        AgentAccount acc2 = _enroll(reg, 2, vm.addr(k2), me);
        usd.mint(address(acc2), 100e6);

        uint256 id = abi.decode(
            _agentDoes(k1, acc1, address(nft), abi.encodeCall(nft.mint, (keccak256("any content: art, document, position")))),
            (uint256)
        );
        _agentDoes(k1, acc1, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _agentDoes(k1, acc1, address(swap), abi.encodeCall(swap.list, (IERC721(address(nft)), id, IERC20(address(usd)), PRICE, address(0))));
        _agentDoes(k2, acc2, address(usd), abi.encodeCall(usd.approve, (address(swap), PRICE)));
        _agentDoes(k2, acc2, address(swap), abi.encodeCall(swap.buy, (IERC721(address(nft)), id, IERC20(address(usd)), PRICE)));
        vm.stopBroadcast();

        require(nft.ownerOf(id) == address(acc2), "sale failed");
        require(usd.balanceOf(address(acc1)) == PRICE, "payment failed");
        console.log("registry  ", address(reg));
        console.log("collection", address(nft));
        console.log("swap      ", address(swap));
        console.log("testUSD   ", address(usd));
        console.log("agent 1   ", address(acc1));
        console.log("agent 2   ", address(acc2));
        console.log("token id  ", id);
    }
}
