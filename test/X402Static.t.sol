// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// The parts of Circle's FiatTokenV2_2 (USDC) used here.
interface IUSDCForStatic {
    function initialize(string memory, string memory, string memory, uint8, address, address, address, address) external;
    function initializeV2(string calldata) external;
    function initializeV2_1(address) external;
    function initializeV2_2(address[] calldata, string calldata) external;
    function configureMinter(address, uint256) external returns (bool);
    function mint(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transferWithAuthorization(address, address, uint256, uint256, uint256, bytes32, bytes memory) external;
}

/// A contract payer whose ERC-1271 check answers yes, and can try to keep a count while doing so.
contract CountingPayer {
    bool public immutable counts;
    uint256 public signed;

    constructor(bool counts_) {
        counts = counts_;
    }

    function isValidSignature(bytes32, bytes calldata) external returns (bytes4) {
        if (counts) signed++;
        return 0x1626ba7e;
    }
}

/// Step 3.1: USDC asks a contract payer about its signature through a read-only call. An x402
/// payment can therefore not be counted against a budget by the payer's account when it is
/// signed: an account that tries is refused. A budget has to sit where the money is.
contract X402StaticTest is Test {
    IUSDCForStatic usdc;
    address constant SIGNATURE_CHECKER = 0x00000000000000000000000000000000005167C4;

    function setUp() public {
        vm.etch(
            SIGNATURE_CHECKER, vm.parseJsonBytes(vm.readFile("test/usdc/SignatureChecker.json"), ".deployedBytecode")
        );
        usdc = IUSDCForStatic(deployCode("test/usdc/FiatTokenV2_2.json"));
        usdc.initialize("USD Coin", "USDC", "USD", 6, address(this), address(this), address(this), address(this));
        usdc.initializeV2("USD Coin");
        usdc.initializeV2_1(address(0xdead));
        usdc.initializeV2_2(new address[](0), "USDC");
        usdc.configureMinter(address(this), type(uint256).max);
    }

    function _pay(CountingPayer payer) internal {
        usdc.transferWithAuthorization(
            address(payer), address(0xBEEF), 1, 0, block.timestamp + 60, bytes32(uint256(1)), hex"00"
        );
    }

    function test_APayerThatOnlyReadsPays() public {
        CountingPayer payer = new CountingPayer(false);
        usdc.mint(address(payer), 10);
        _pay(payer);
        assertEq(usdc.balanceOf(address(0xBEEF)), 1);
    }

    function test_APayerThatCountsIsRefused() public {
        CountingPayer payer = new CountingPayer(true);
        usdc.mint(address(payer), 10);
        vm.expectRevert("FiatTokenV2: invalid signature");
        _pay(payer);
        assertEq(payer.signed(), 0);
    }
}
