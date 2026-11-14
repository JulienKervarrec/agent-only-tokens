// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {AgentAccount} from "../src/AgentAccount.sol";
import {AgentOnlyBase} from "./AgentOnly.t.sol";

/// The parts of Circle's FiatTokenV2_2 (USDC) used here.
interface IUSDC {
    function initialize(string memory, string memory, string memory, uint8, address, address, address, address) external;
    function initializeV2(string calldata newName) external;
    function initializeV2_1(address lostAndFound) external;
    function initializeV2_2(address[] calldata accountsToBlacklist, string calldata newSymbol) external;
    function configureMinter(address minter, uint256 allowance) external returns (bool);
    function mint(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external;
}

/// An x402 `exact` payment is an EIP-3009 authorisation on USDC, signed by the payer and submitted
/// by a facilitator. These tests run against Circle's own FiatTokenV2_2 code (see test/usdc) and
/// replay the two steps of the x402 reference facilitator for a payer that is a contract:
/// it asks the payer `isValidSignature` (ERC-1271), then calls `transferWithAuthorization`.
contract X402Test is AgentOnlyBase {
    IUSDC realUsdc;
    address facilitator = address(0xFAC);
    address merchant = address(0x5E11);

    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    address constant SIGNATURE_CHECKER = 0x00000000000000000000000000000000005167C4; // library address the token was linked with

    struct Payment {
        address from;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
    }

    function setUp() public override {
        super.setUp();
        vm.etch(
            SIGNATURE_CHECKER, vm.parseJsonBytes(vm.readFile("test/usdc/SignatureChecker.json"), ".deployedBytecode")
        );
        realUsdc = IUSDC(deployCode("test/usdc/FiatTokenV2_2.json"));
        realUsdc.initialize("USD Coin", "USDC", "USD", 6, address(this), address(this), address(this), address(this));
        realUsdc.initializeV2("USD Coin");
        realUsdc.initializeV2_1(address(0xdead));
        realUsdc.initializeV2_2(new address[](0), "USDC");
        realUsdc.configureMinter(address(this), type(uint256).max);
        realUsdc.mint(address(acc1), 100e6);
    }

    function _digest(Payment memory p) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH, p.from, p.to, p.value, p.validAfter, p.validBefore, p.nonce
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", realUsdc.DOMAIN_SEPARATOR(), structHash));
    }

    /// What the agent's x402 client does: the session key approves the payment digest
    /// as a message of its account.
    function _agentSigns(uint256 pk, AgentAccount acc, Payment memory p) internal view returns (bytes memory) {
        return _sign(pk, acc.messageDigest(_digest(p)));
    }

    /// The facilitator's settlement for a 65-byte signature: the (v, r, s) form.
    function _settle(Payment memory p, bytes memory sig) internal {
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        vm.prank(facilitator);
        realUsdc.transferWithAuthorization(p.from, p.to, p.value, p.validAfter, p.validBefore, p.nonce, v, r, s);
    }

    function test_AgentPaysAnX402Invoice() public {
        Payment memory p = Payment(address(acc1), merchant, 2e6, 0, NOW + 60, keccak256("invoice-1"));
        bytes memory sig = _agentSigns(K1, acc1, p);
        assertEq(sig.length, 65);
        // Facilitator, step 1 (verify): the payer has code, so it is asked through ERC-1271.
        assertEq(acc1.isValidSignature(_digest(p), sig), bytes4(0x1626ba7e));
        // Facilitator, step 2 (settle): USDC itself asks the account again. The agent needs no ETH.
        _settle(p, sig);
        assertEq(realUsdc.balanceOf(merchant), 2e6);
        assertEq(realUsdc.balanceOf(address(acc1)), 98e6);
        // The same authorisation cannot be settled twice.
        vm.expectRevert("FiatTokenV2: authorization is used or canceled");
        this.settle(p, sig);
    }

    function settle(Payment memory p, bytes memory sig) external {
        _settle(p, sig);
    }

    function test_BytesFormWorksToo() public {
        Payment memory p = Payment(address(acc1), address(acc2), 5e6, 0, NOW + 60, keccak256("invoice-2"));
        bytes memory sig = _agentSigns(K1, acc1, p);
        vm.prank(facilitator);
        realUsdc.transferWithAuthorization(p.from, p.to, p.value, p.validAfter, p.validBefore, p.nonce, sig);
        assertEq(realUsdc.balanceOf(address(acc2)), 5e6); // one agent paid another
    }

    function test_OnlyTheAgentsLiveKeyCanPay() public {
        Payment memory p = Payment(address(acc1), merchant, 2e6, 0, NOW + 60, keccak256("invoice-3"));
        // A human key, another agent's key, or the right key signing the raw digest: all refused.
        bytes[3] memory bad = [_agentSigns(HUMAN_PK, acc1, p), _agentSigns(K2, acc1, p), _sign(K1, _digest(p))];
        for (uint256 i; i < 3; ++i) {
            assertEq(acc1.isValidSignature(_digest(p), bad[i]), bytes4(0xffffffff));
            vm.expectRevert("FiatTokenV2: invalid signature");
            this.settle(p, bad[i]);
        }
        // A frozen agent cannot pay, even with a signature made before the freeze.
        bytes memory sig = _agentSigns(K1, acc1, p);
        vm.prank(SPONSOR1);
        reg.setFrozen(1, true);
        vm.expectRevert("FiatTokenV2: invalid signature");
        this.settle(p, sig);
        vm.prank(SPONSOR1);
        reg.setFrozen(1, false);
        // Changing any term of the payment invalidates the signature.
        Payment memory more = Payment(p.from, p.to, 50e6, p.validAfter, p.validBefore, p.nonce);
        vm.expectRevert("FiatTokenV2: invalid signature");
        this.settle(more, sig);
        _settle(p, sig);
        assertEq(realUsdc.balanceOf(merchant), 2e6);
    }

    function test_AgentIsPaidByAnOrdinaryWallet() public {
        // A human customer pays an agent's service the usual x402 way.
        address customer = vm.addr(HUMAN_PK);
        realUsdc.mint(customer, 10e6);
        Payment memory p = Payment(customer, address(acc2), 3e6, 0, NOW + 60, keccak256("invoice-4"));
        _settle(p, _sign(HUMAN_PK, _digest(p)));
        assertEq(realUsdc.balanceOf(address(acc2)), 3e6);
    }
}
