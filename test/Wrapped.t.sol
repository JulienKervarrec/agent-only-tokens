// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAgentRegistry} from "../src/IAgentRegistry.sol";
import {ERC721AgentOnly} from "../src/ERC721AgentOnly.sol";
import {AgentAccount} from "../src/AgentAccount.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";
import {AgentSwap} from "../src/AgentSwap.sol";
import {AgentWrapped721} from "../src/AgentWrapped721.sol";
import {AgentWrappedUniV3} from "../src/AgentWrappedUniV3.sol";

contract Coin is ERC20 {
    constructor(string memory s) ERC20(s, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Any classic NFT, with no restriction at all.
contract ClassicNFT is ERC721 {
    constructor() ERC721("Classic", "CLS") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "ipfs://original";
    }
}

/// Functions of the Uniswap V3 position manager used by the test.
interface INPM is IERC721 {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function positions(uint256 tokenId)
        external
        view
        returns (uint96, address, address, address, uint24, int24, int24, uint128 liquidity, uint256, uint256, uint128, uint128);
}

interface IPool {
    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data)
        external
        returns (int256 amount0, int256 amount1);
}

contract WrappedTest is Test {
    /// Payment for a Uniswap V3 swap started by this test (a third party swapping in the pool).
    function uniswapV3SwapCallback(int256 amount0Delta, int256, bytes calldata data) external {
        IERC20(abi.decode(data, (address))).transfer(msg.sender, uint256(amount0Delta));
    }

    AttestedAgentRegistry reg;
    AgentSwap swap;
    AgentAccount acc1;
    AgentAccount acc2;
    Coin usdc;

    uint256 constant K1 = 0x0101010101010101010101010101010101010101010101010101010101010101;
    uint256 constant K2 = 0x0202020202020202020202020202020202020202020202020202020202020202;
    uint256 constant A1 = 0xA1;
    uint256 constant A2 = 0xA2;
    address constant HUMAN = address(0x4);
    uint64 constant FAR = 10_000_000;
    uint256 constant BOND = 0.01 ether;

    function setUp() public {
        vm.warp(1_000);
        address[] memory att = new address[](2);
        att[0] = vm.addr(A1);
        att[1] = vm.addr(A2);
        reg = new AttestedAgentRegistry(att, 2, BOND, 30 days, IERC721(address(0)));
        swap = new AgentSwap();
        usdc = new Coin("USDC");
        vm.deal(address(this), 1 ether);
        acc1 = _enroll(1, vm.addr(K1));
        acc2 = _enroll(2, vm.addr(K2));
        reg.setVenue(address(swap), true, bytes32(0), _attest(reg.hashVenue(address(swap), true, bytes32(0))));
        usdc.mint(address(acc2), 1_000);
    }

    function _attest(bytes32 digest) internal pure returns (bytes[] memory sigs) {
        (uint256 a, uint256 b) = vm.addr(A1) < vm.addr(A2) ? (A1, A2) : (A2, A1);
        sigs = new bytes[](2);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(a, digest);
        sigs[0] = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(b, digest);
        sigs[1] = abi.encodePacked(r, s, v);
    }

    function _enroll(uint256 id, address key) internal returns (AgentAccount) {
        bytes32 d = reg.hashEnrollment(id, key, bytes32(0), address(this), 0, FAR);
        reg.enroll{value: BOND}(id, key, bytes32(0), FAR, _attest(d));
        return AgentAccount(payable(reg.accountOf(id)));
    }

    function _do(uint256 pk, AgentAccount acc, address target, bytes memory data) internal returns (bytes memory) {
        vm.prank(vm.addr(pk));
        return acc.execute(target, 0, data);
    }

    function _ids(uint256 id) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = id;
    }

    // ------------------------------------------------------------ generic wrapper

    function test_WrapAnyClassicNft() public {
        ClassicNFT classic = new ClassicNFT();
        AgentWrapped721 w = new AgentWrapped721(classic, IAgentRegistry(address(reg)), true, "Wrapped", "wCLS");
        classic.mint(address(acc1), 7);

        // The agent wraps its classic NFT.
        _do(K1, acc1, address(classic), abi.encodeCall(classic.approve, (address(w), 7)));
        _do(K1, acc1, address(w), abi.encodeCall(w.depositFor, (address(acc1), _ids(7))));
        assertEq(classic.ownerOf(7), address(w));
        assertEq(w.ownerOf(7), address(acc1));
        assertEq(w.tokenURI(7), "ipfs://original");

        // Once wrapped, it can no longer go to a human, nor be approved for one.
        vm.expectRevert(abi.encodeWithSelector(ERC721AgentOnly.NotAgent.selector, HUMAN));
        _do(K1, acc1, address(w), abi.encodeCall(w.approve, (HUMAN, 7)));

        // A human cannot wrap an NFT for themselves either.
        classic.mint(HUMAN, 8);
        vm.startPrank(HUMAN);
        classic.approve(address(w), 8);
        vm.expectRevert(abi.encodeWithSelector(ERC721AgentOnly.NotAgent.selector, HUMAN));
        w.depositFor(HUMAN, _ids(8));
        vm.stopPrank();

        // Sale to another agent, who becomes the only one able to withdraw it.
        _do(K1, acc1, address(w), abi.encodeCall(w.approve, (address(swap), 7)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (w, 7, usdc, 100, address(0))));
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(swap), 100)));
        _do(K2, acc2, address(swap), abi.encodeCall(swap.buy, (w, 7, 100)));
        assertEq(w.ownerOf(7), address(acc2));

        vm.expectRevert();
        _do(K1, acc1, address(w), abi.encodeCall(w.withdrawTo, (address(acc1), _ids(7))));
        // Withdrawal: only to its own account.
        vm.expectRevert(AgentWrapped721.OnlyToSelf.selector);
        _do(K2, acc2, address(w), abi.encodeCall(w.withdrawTo, (HUMAN, _ids(7))));
        _do(K2, acc2, address(w), abi.encodeCall(w.withdrawTo, (address(acc2), _ids(7))));
        assertEq(classic.ownerOf(7), address(acc2));
    }

    // ------------------------------------------------------------ real Uniswap V3 position

    function test_RealUniswapV3Position() public {
        // Official Uniswap V3 contracts, deployed from the artifacts published on npm.
        address factory = deployCode("node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json");
        INPM npm = INPM(
            deployCode(
                "node_modules/@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json",
                abi.encode(factory, address(0xEEEE), address(0))
            )
        );
        Coin x = new Coin("X");
        Coin y = new Coin("Y");
        (Coin t0, Coin t1) = address(x) < address(y) ? (x, y) : (y, x);
        address pool = npm.createAndInitializePoolIfNecessary(address(t0), address(t1), 3000, 2 ** 96);

        // Agent 1 creates a liquidity position in its own name, like any user.
        t0.mint(address(acc1), 1_000_000);
        t1.mint(address(acc1), 1_000_000);
        _do(K1, acc1, address(t0), abi.encodeCall(t0.approve, (address(npm), 1_000_000)));
        _do(K1, acc1, address(t1), abi.encodeCall(t1.approve, (address(npm), 1_000_000)));
        bytes memory ret = _do(
            K1,
            acc1,
            address(npm),
            abi.encodeCall(
                npm.mint,
                (INPM.MintParams(address(t0), address(t1), 3000, -600, 600, 1_000_000, 1_000_000, 0, 0, address(acc1), FAR))
            )
        );
        (uint256 id, uint128 liquidity, uint256 _used0,) = abi.decode(ret, (uint256, uint128, uint256, uint256));
        assertEq(npm.ownerOf(id), address(acc1));
        assertGt(liquidity, 0);

        // It wraps it: the position becomes agent-only and will never leave.
        AgentWrappedUniV3 w = new AgentWrappedUniV3(npm, IAgentRegistry(address(reg)));
        _do(K1, acc1, address(npm), abi.encodeCall(npm.approve, (address(w), id)));
        _do(K1, acc1, address(w), abi.encodeCall(w.depositFor, (address(acc1), _ids(id))));
        assertEq(npm.ownerOf(id), address(w));
        assertEq(w.ownerOf(id), address(acc1));
        vm.expectRevert(AgentWrapped721.NotUnwrappable.selector);
        _do(K1, acc1, address(w), abi.encodeCall(w.withdrawTo, (address(acc1), _ids(id))));

        // A third party swaps in the pool: the position earns fees.
        t0.mint(address(this), 10_000);
        IPool(pool).swap(address(this), true, 10_000, 4295128740, abi.encode(address(t0)));

        // Sale of the position to agent 2.
        _do(K1, acc1, address(w), abi.encodeCall(w.approve, (address(swap), id)));
        _do(K1, acc1, address(swap), abi.encodeCall(swap.list, (w, id, usdc, 500, address(0))));
        _do(K2, acc2, address(usdc), abi.encodeCall(usdc.approve, (address(swap), 500)));
        _do(K2, acc2, address(swap), abi.encodeCall(swap.buy, (w, id, 500)));
        assertEq(w.ownerOf(id), address(acc2));

        // The previous holder and a human no longer control the position.
        vm.expectRevert(AgentWrappedUniV3.NotAuthorized.selector);
        _do(K1, acc1, address(w), abi.encodeCall(w.collect, (id)));
        vm.prank(HUMAN);
        vm.expectRevert(AgentWrappedUniV3.NotAuthorized.selector);
        w.decreaseLiquidity(id, liquidity, 0, 0, FAR);

        // The new holder first collects the fees earned by the position...
        _do(K2, acc2, address(w), abi.encodeCall(w.collect, (id)));
        uint256 fees = t0.balanceOf(address(acc2));
        assertGt(fees, 0);
        assertLt(fees, 31); // 0.3% of 10,000
        assertEq(t0.balanceOf(address(acc1)), 0 + (1_000_000 - _used0));

        // ... then removes the liquidity and collects the tokens to its account.
        _do(K2, acc2, address(w), abi.encodeCall(w.decreaseLiquidity, (id, liquidity, 0, 0, FAR)));
        _do(K2, acc2, address(w), abi.encodeCall(w.collect, (id)));
        (,,,,,,, uint128 left,,,,) = npm.positions(id);
        assertEq(left, 0);
        assertGt(t0.balanceOf(address(acc2)), 1_000_000);
        assertGt(t1.balanceOf(address(acc2)), 980_000);
        // The position itself never left the wrapper.
        assertEq(npm.ownerOf(id), address(w));
    }
}
