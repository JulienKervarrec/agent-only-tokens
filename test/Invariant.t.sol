// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentSwap} from "../src/AgentSwap.sol";
import {AgentLoan} from "../src/AgentLoan.sol";
import {AgentOnlyBase, AnyCollection, RogueWrapper} from "./AgentOnly.t.sol";

/// Random actors hammer the token: two agents, a human, and an unapproved contract.
/// Every call may fail; what matters is the state left behind.
contract Handler is Test {
    AttestedAgentRegistry reg;
    AnyCollection nft;
    AgentSwap swap;
    AgentLoan loan;
    IERC20 usdc;
    AgentAccount[2] acc;
    uint256[2] key;
    address[2] sponsor;
    address human;
    address rogue;

    uint256[] public ids;
    uint256 public moves; // successful changes of holder, mints included

    struct Setup {
        AttestedAgentRegistry reg;
        AnyCollection nft;
        AgentSwap swap;
        AgentLoan loan;
        IERC20 usdc;
        AgentAccount[2] acc;
        uint256[2] key;
        address[2] sponsor;
        address human;
        address rogue;
    }

    constructor(Setup memory s) {
        reg = s.reg;
        nft = s.nft;
        swap = s.swap;
        loan = s.loan;
        usdc = s.usdc;
        acc = s.acc;
        key = s.key;
        sponsor = s.sponsor;
        human = s.human;
        rogue = s.rogue;
    }

    function idsLength() external view returns (uint256) {
        return ids.length;
    }

    function _party(uint256 seed) private view returns (address) {
        address[6] memory p = [address(acc[0]), address(acc[1]), human, rogue, address(swap), address(loan)];
        return p[seed % 6];
    }

    function _id(uint256 seed) private view returns (uint256) {
        return ids.length == 0 ? 0 : ids[seed % ids.length];
    }

    function _owner(uint256 id) private view returns (address) {
        try nft.ownerOf(id) returns (address o) {
            return o;
        } catch {
            return address(0);
        }
    }

    /// An agent acts through its account. Returns whether the call went through.
    function _agent(uint256 a, address target, bytes memory data) private returns (bool ok) {
        vm.prank(vm.addr(key[a % 2]));
        try acc[a % 2].execute(target, 0, data) {
            ok = true;
        } catch {}
    }

    /// The human, or the unapproved contract's deployer, calls the token directly.
    function _outsider(uint256 who, address target, bytes memory data) private returns (bool ok) {
        vm.prank(who % 2 == 0 ? human : rogue);
        (ok,) = target.call(data);
    }

    function _track(uint256 id, address before) private {
        if (_owner(id) != before) moves++;
    }

    // ---------------------------------------------------------------- actions

    function mint(uint256 a) external {
        bytes memory data = abi.encodeCall(nft.mint, (bytes32(ids.length)));
        vm.prank(vm.addr(key[a % 2]));
        try acc[a % 2].execute(address(nft), 0, data) returns (bytes memory ret) {
            ids.push(abi.decode(ret, (uint256)));
            moves++;
        } catch {}
    }

    function outsiderMints(uint256 who) external {
        _outsider(who, address(nft), abi.encodeCall(nft.mint, (bytes32(uint256(1)))));
    }

    function approve(uint256 a, uint256 idSeed, uint256 toSeed) external {
        _agent(a, address(nft), abi.encodeCall(nft.approve, (_party(toSeed), _id(idSeed))));
    }

    function approveAll(uint256 a, uint256 toSeed, bool on) external {
        _agent(a, address(nft), abi.encodeCall(nft.setApprovalForAll, (_party(toSeed), on)));
    }

    function agentTransfers(uint256 a, uint256 idSeed, uint256 toSeed, bool safe) external {
        uint256 id = _id(idSeed);
        address from = _owner(id);
        bytes memory data = safe
            ? abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", from, _party(toSeed), id)
            : abi.encodeCall(nft.transferFrom, (from, _party(toSeed), id));
        _agent(a, address(nft), data);
        _track(id, from);
    }

    function outsiderTransfers(uint256 who, uint256 idSeed, uint256 toSeed) external {
        uint256 id = _id(idSeed);
        address from = _owner(id);
        _outsider(who, address(nft), abi.encodeCall(nft.transferFrom, (from, _party(toSeed), id)));
        _track(id, from);
    }

    /// The regular way to give a token: the holder approves the other agent, who pulls it.
    function handOver(uint256 idSeed) external {
        uint256 id = _id(idSeed);
        address from = _owner(id);
        uint256 holder = from == address(acc[0]) ? 0 : 1;
        _agent(holder, address(nft), abi.encodeCall(nft.approve, (address(acc[1 - holder]), id)));
        _agent(1 - holder, address(nft), abi.encodeCall(nft.transferFrom, (from, address(acc[1 - holder]), id)));
        _track(id, from);
    }

    function burn(uint256 a, uint256 idSeed) external {
        _agent(a, address(nft), abi.encodeCall(nft.burn, (_id(idSeed))));
    }

    function list(uint256 a, uint256 idSeed, uint256 price) external {
        uint256 id = _id(idSeed);
        _agent(a, address(nft), abi.encodeCall(nft.approve, (address(swap), id)));
        _agent(a, address(swap), abi.encodeCall(swap.list, (nft, id, usdc, price % 50, address(0))));
    }

    function agentBuys(uint256 a, uint256 idSeed) external {
        uint256 id = _id(idSeed);
        address from = _owner(id);
        (,,, uint256 price) = swap.listings(nft, id);
        _agent(a, address(usdc), abi.encodeCall(usdc.approve, (address(swap), price)));
        _agent(a, address(swap), abi.encodeCall(swap.buy, (nft, id, usdc, price)));
        _track(id, from);
    }

    function outsiderBuys(uint256 who, uint256 idSeed) external {
        uint256 id = _id(idSeed);
        address from = _owner(id);
        (,,, uint256 price) = swap.listings(nft, id);
        _outsider(who, address(usdc), abi.encodeCall(usdc.approve, (address(swap), price)));
        _outsider(who, address(swap), abi.encodeCall(swap.buy, (nft, id, usdc, price)));
        _track(id, from);
    }

    function offer(uint256 a, uint256 idSeed, uint64 duration) external {
        uint256 id = _id(idSeed);
        address from = _owner(id);
        _agent(a, address(nft), abi.encodeCall(nft.approve, (address(loan), id)));
        _agent(a, address(loan), abi.encodeCall(loan.offer, (nft, id, usdc, 10, 11, duration % 1000)));
        _track(id, from);
    }

    function fund(uint256 who, uint256 idSeed, bool byAgent) external {
        uint256 id = _id(idSeed);
        (,,,,, uint64 duration,) = loan.loans(nft, id);
        bytes memory data = abi.encodeCall(loan.fund, (nft, id, usdc, 10, 11, duration));
        if (byAgent) {
            _agent(who, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 10)));
            _agent(who, address(loan), data);
        } else {
            _outsider(who, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 10)));
            _outsider(who, address(loan), data); // a human may lend, but can never receive the token
        }
    }

    function settle(uint256 who, uint256 idSeed, uint8 action, bool byAgent, uint16 wait) external {
        uint256 id = _id(idSeed);
        address from = _owner(id);
        vm.warp(block.timestamp + wait);
        bytes memory data = action % 3 == 0
            ? abi.encodeCall(loan.repay, (nft, id))
            : action % 3 == 1 ? abi.encodeCall(loan.claim, (nft, id)) : abi.encodeCall(loan.cancel, (nft, id));
        if (byAgent) {
            _agent(who, address(usdc), abi.encodeCall(usdc.approve, (address(loan), 11)));
            _agent(who, address(loan), data);
        } else {
            _outsider(who, address(loan), data);
        }
        _track(id, from);
    }

    /// Freezes rarely and unfreezes often, so that most of a run happens with live agents.
    function freeze(uint256 a, uint8 dice) external {
        vm.prank(sponsor[a % 2]);
        reg.setFrozen(a % 2 + 1, dice % 8 == 0);
    }
}

contract InvariantTest is AgentOnlyBase {
    Handler handler;
    address rogue;

    function setUp() public override {
        super.setUp();
        rogue = address(new RogueWrapper());
        usdc.mint(human, 1_000);
        usdc.mint(rogue, 1_000);
        handler = new Handler(
            Handler.Setup(
                reg, nft, swap, loan, IERC20(address(usdc)), [acc1, acc2], [K1, K2], [SPONSOR1, SPONSOR2], human, rogue
            )
        );
        for (uint256 i; i < 4; ++i) {
            handler.mint(i); // two tokens per agent to start from
        }
        targetContract(address(handler));
    }

    /// Whatever anyone does, a token is only ever held by an agent account or an approved venue,
    /// and only they can be approved for it.
    function invariant_OnlyAgentsAndVenuesHoldOrAreApproved() public view {
        assertEq(nft.balanceOf(human), 0);
        assertEq(nft.balanceOf(rogue), 0);
        for (uint256 i; i < handler.idsLength(); ++i) {
            uint256 id = handler.ids(i);
            address owner;
            try nft.ownerOf(id) returns (address o) {
                owner = o;
            } catch {
                continue; // burned
            }
            assertTrue(_isParty(owner), "holder is neither an agent nor a venue");
            address approved = nft.getApproved(id);
            assertTrue(approved == address(0) || _isParty(approved), "approved address is neither an agent nor a venue");
        }
        address[4] memory holders = [address(acc1), address(acc2), address(swap), address(loan)];
        for (uint256 i; i < 4; ++i) {
            assertFalse(nft.isApprovedForAll(holders[i], human));
            assertFalse(nft.isApprovedForAll(holders[i], rogue));
        }
    }

    function _isParty(address a) private view returns (bool) {
        return a == address(acc1) || a == address(acc2) || a == address(swap) || a == address(loan);
    }

    /// Shows that the random actions are not all refused: tokens do change hands during a run.
    function afterInvariant() public {
        emit log_named_uint("tokens minted", handler.idsLength());
        emit log_named_uint("changes of holder", handler.moves());
    }
}
