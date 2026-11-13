// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentOnlyNFT, IAgentRegistry} from "../src/AgentOnlyNFT.sol";
import {AgentOnlyNFTWithVault} from "../src/AgentOnlyNFTWithVault.sol";
import {AttestedAgentRegistry} from "../src/AttestedAgentRegistry.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AgentOnlyNFTTest is Test {
    AgentOnlyNFTWithVault nft;
    AttestedAgentRegistry reg;
    MockUSDC usdc;

    // Cles de session des agents 1 et 2, et un wallet humain.
    uint256 constant K1 = 0x0101010101010101010101010101010101010101010101010101010101010101;
    uint256 constant K2 = 0x0202020202020202020202020202020202020202020202020202020202020202;
    uint256 constant HUMAN = 0x0909090909090909090909090909090909090909090909090909090909090909;
    // Trois attesteurs, seuil de deux.
    uint256 constant A1 = 0xA1;
    uint256 constant A2 = 0xA2;
    uint256 constant A3 = 0xA3;

    address constant SPONSOR1 = address(0x101);
    address constant SPONSOR2 = address(0x102);
    address constant FEES = address(0xFEE5);
    uint64 constant NOW = 1_000;
    uint64 constant FAR = 10_000_000;
    uint256 constant BOND = 0.01 ether;
    uint256 constant FEE = 0.001 ether;
    uint64 constant TTL = 30 days;

    function setUp() public {
        vm.chainId(8453);
        vm.warp(NOW);
        address[] memory att = new address[](3);
        att[0] = vm.addr(A1);
        att[1] = vm.addr(A2);
        att[2] = vm.addr(A3);
        reg = new AttestedAgentRegistry(att, 2, BOND, TTL);
        usdc = new MockUSDC();
        // Frais de mint 0,001 ETH, 3 mints par agent et par jour.
        nft = new AgentOnlyNFTWithVault(IAgentRegistry(address(reg)), FEE, FEES, 3, 1 days, IERC20(address(usdc)));

        vm.deal(SPONSOR1, 1 ether);
        vm.deal(SPONSOR2, 1 ether);
        vm.deal(address(this), 10 ether);
        _enroll(SPONSOR1, 1, vm.addr(K1), BOND);
        _enroll(SPONSOR2, 2, vm.addr(K2), BOND);

        usdc.mint(address(this), 2_000);
        usdc.approve(address(nft), 2_000);
        nft.deposit(1, 1_000);
        nft.deposit(2, 1_000);
    }

    // ------------------------------------------------------------ outils

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// Deux signatures d'attesteurs, triees par adresse croissante.
    function _attest(uint256 pkA, uint256 pkB, bytes32 digest) internal pure returns (bytes[] memory sigs) {
        if (vm.addr(pkA) > vm.addr(pkB)) (pkA, pkB) = (pkB, pkA);
        sigs = new bytes[](2);
        sigs[0] = _sign(pkA, digest);
        sigs[1] = _sign(pkB, digest);
    }

    function _enrollDigest(address sponsor, uint256 agent, address key) internal view returns (bytes32) {
        return reg.hashEnrollment(agent, key, keccak256("preuve"), sponsor, reg.enrollmentNonce(agent), FAR);
    }

    function _enroll(address sponsor, uint256 agent, address key, uint256 value) internal {
        bytes[] memory sigs = _attest(A1, A2, _enrollDigest(sponsor, agent, key));
        vm.prank(sponsor);
        reg.enroll{value: value}(agent, key, keccak256("preuve"), FAR, sigs);
    }

    function _t(AgentOnlyNFT.Op op, uint128 amount, uint128 repay, uint64 until)
        internal
        pure
        returns (AgentOnlyNFT.Terms memory)
    {
        return AgentOnlyNFT.Terms(op, bytes32(0), amount, repay, until);
    }

    function _s(AgentOnlyNFT.Op op) internal pure returns (AgentOnlyNFT.Terms memory) {
        return _t(op, 0, 0, 0);
    }

    function _intent(AgentOnlyNFT.Terms memory t, uint256 id, uint256 agent, uint256 cp)
        internal
        view
        returns (AgentOnlyNFT.Intent memory)
    {
        uint256 n = t.op == AgentOnlyNFT.Op.Mint ? nft.mintNonce(agent) : nft.nonceOf(id);
        return AgentOnlyNFT.Intent(uint8(t.op), id, agent, cp, nft.termsHash(t), n, FAR);
    }

    function _one(uint256 pk, AgentOnlyNFT.Terms memory t, uint256 id, uint256 agent)
        internal
        view
        returns (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs)
    {
        its = new AgentOnlyNFT.Intent[](1);
        sigs = new bytes[](1);
        its[0] = _intent(t, id, agent, 0);
        sigs[0] = _sign(pk, nft.hashIntent(its[0]));
    }

    function _two(uint256 pkA, uint256 a, uint256 pkB, uint256 b, AgentOnlyNFT.Terms memory t, uint256 id)
        internal
        view
        returns (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs)
    {
        its = new AgentOnlyNFT.Intent[](2);
        sigs = new bytes[](2);
        its[0] = _intent(t, id, a, b);
        its[1] = _intent(t, id, b, a);
        sigs[0] = _sign(pkA, nft.hashIntent(its[0]));
        sigs[1] = _sign(pkB, nft.hashIntent(its[1]));
    }

    function _exec1(uint256 pk, AgentOnlyNFT.Terms memory t, uint256 id, uint256 agent) internal {
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _one(pk, t, id, agent);
        nft.execute(id, t, its, sigs);
    }

    function _exec2(uint256 pkA, uint256 a, uint256 pkB, uint256 b, AgentOnlyNFT.Terms memory t, uint256 id)
        internal
    {
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(pkA, a, pkB, b, t, id);
        nft.execute(id, t, its, sigs);
    }

    function _mint(uint256 pk, uint256 agent) internal returns (uint256) {
        AgentOnlyNFT.Terms memory t = AgentOnlyNFT.Terms(AgentOnlyNFT.Op.Mint, bytes32(uint256(7)), 0, 0, 0);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _one(pk, t, 0, agent);
        return nft.execute{value: FEE}(0, t, its, sigs);
    }

    // ------------------------------------------------------------ cycle de vie

    function test_Lifecycle() public {
        uint256 id = _mint(K1, 1);
        assertEq(nft.ownerOf(id), nft.holderAddress(1));
        assertEq(FEES.balance, FEE);

        // Don, puis vente : NFT et USDC bougent dans la meme transaction.
        _exec2(K1, 1, K2, 2, _s(AgentOnlyNFT.Op.Transfer), id);
        assertEq(nft.agentOf(id), 2);
        _exec2(K2, 2, K1, 1, _t(AgentOnlyNFT.Op.Transfer, 300, 0, 0), id);
        assertEq(nft.agentOf(id), 1);
        assertEq(nft.vaultBalance(1), 700);
        assertEq(nft.vaultBalance(2), 1_300);

        // Staking : verrou personnel, sortie apres l'echeance.
        _exec1(K1, _t(AgentOnlyNFT.Op.Lock, 0, 0, NOW + 100), id, 1);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _one(K1, _s(AgentOnlyNFT.Op.Unlock), id, 1);
        vm.warp(NOW + 50);
        vm.expectRevert(AgentOnlyNFT.StillLocked.selector);
        nft.execute(id, _s(AgentOnlyNFT.Op.Unlock), its, sigs);
        vm.warp(NOW + 100);
        nft.execute(id, _s(AgentOnlyNFT.Op.Unlock), its, sigs);

        // Pret sur gage rembourse : 400 recus, 440 rendus.
        _exec2(K1, 1, K2, 2, _t(AgentOnlyNFT.Op.Lock, 400, 440, NOW + 900), id);
        assertEq(nft.vaultBalance(1), 1_100);
        _exec1(K1, _s(AgentOnlyNFT.Op.Unlock), id, 1);
        assertEq(nft.vaultBalance(1), 660);
        assertEq(nft.vaultBalance(2), 1_340);

        // Pret en defaut : le preteur saisit le token apres l'echeance.
        _exec2(K1, 1, K2, 2, _t(AgentOnlyNFT.Op.Lock, 100, 110, NOW + 1_000), id);
        (its, sigs) = _one(K2, _s(AgentOnlyNFT.Op.Claim), id, 2);
        vm.warp(NOW + 1_000);
        vm.expectRevert(AgentOnlyNFT.NotDue.selector);
        nft.execute(id, _s(AgentOnlyNFT.Op.Claim), its, sigs);
        vm.warp(NOW + 1_001);
        nft.execute(id, _s(AgentOnlyNFT.Op.Claim), its, sigs);
        assertEq(nft.agentOf(id), 2);

        _exec1(K2, _s(AgentOnlyNFT.Op.Burn), id, 2);
        vm.expectRevert(AgentOnlyNFT.NoToken.selector);
        nft.ownerOf(id);
        assertEq(nft.vaultBalance(1) + nft.vaultBalance(2), 2_000);
        assertEq(usdc.balanceOf(address(nft)), 2_000);
    }

    // ------------------------------------------------------------ les trois regles du standard

    function test_StandardWritesAllRevert() public {
        uint256 id = _mint(K1, 1);
        address holder = nft.holderAddress(1);
        vm.startPrank(holder);
        vm.expectRevert(AgentOnlyNFT.TransfersDisabled.selector);
        nft.approve(address(this), id);
        vm.expectRevert(AgentOnlyNFT.TransfersDisabled.selector);
        nft.setApprovalForAll(address(this), true);
        vm.expectRevert(AgentOnlyNFT.TransfersDisabled.selector);
        nft.transferFrom(holder, address(this), id);
        vm.expectRevert(AgentOnlyNFT.TransfersDisabled.selector);
        nft.safeTransferFrom(holder, address(this), id);
        vm.expectRevert(AgentOnlyNFT.TransfersDisabled.selector);
        nft.safeTransferFrom(holder, address(this), id, "");
        vm.stopPrank();
        assertTrue(nft.locked(id));
        assertTrue(nft.supportsInterface(0x80ac58cd));
        assertTrue(nft.supportsInterface(0xb45a3c0e));
    }

    function test_HumanWalletCannotSignOrReceive() public {
        uint256 id = _mint(K1, 1);
        AgentOnlyNFT.Terms memory t = _s(AgentOnlyNFT.Op.Transfer);

        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(HUMAN, 1, K2, 2, t, id);
        vm.expectRevert(AgentOnlyNFT.BadSigner.selector);
        nft.execute(id, t, its, sigs);

        // Destinataire non enrole : refuse, meme s'il cosigne.
        (its, sigs) = _two(K1, 1, HUMAN, 9, t, id);
        vm.expectRevert(AgentOnlyNFT.NotAgent.selector);
        nft.execute(id, t, its, sigs);
        assertEq(nft.agentOf(id), 1);
    }

    function test_NoUnsolicitedToken() public {
        uint256 id = _mint(K1, 1);
        AgentOnlyNFT.Terms memory t = _s(AgentOnlyNFT.Op.Transfer);
        AgentOnlyNFT.Intent[] memory its = new AgentOnlyNFT.Intent[](1);
        bytes[] memory sigs = new bytes[](1);
        its[0] = _intent(t, id, 1, 2);
        sigs[0] = _sign(K1, nft.hashIntent(its[0]));
        vm.expectRevert(AgentOnlyNFT.BadParties.selector);
        nft.execute(id, t, its, sigs);
    }

    // ------------------------------------------------------------ rejeu et relais

    function test_ReplayAndRelayerTampering() public {
        uint256 id = _mint(K1, 1);
        AgentOnlyNFT.Terms memory t = _t(AgentOnlyNFT.Op.Transfer, 100, 0, 0);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(K1, 1, K2, 2, t, id);

        vm.expectRevert(AgentOnlyNFT.TermsMismatch.selector);
        nft.execute(id, _t(AgentOnlyNFT.Op.Transfer, 1, 0, 0), its, sigs);

        its[0].counterparty = 3;
        vm.expectRevert(AgentOnlyNFT.BadSigner.selector);
        nft.execute(id, t, its, sigs);
        its[0].counterparty = 2;

        nft.execute(id, t, its, sigs);
        vm.expectRevert(AgentOnlyNFT.BadNonce.selector);
        nft.execute(id, t, its, sigs);

        AgentOnlyNFT.Terms memory b = _s(AgentOnlyNFT.Op.Burn);
        AgentOnlyNFT.Intent[] memory one = new AgentOnlyNFT.Intent[](1);
        bytes[] memory s1 = new bytes[](1);
        one[0] = AgentOnlyNFT.Intent(uint8(b.op), id, 2, 0, nft.termsHash(b), nft.nonceOf(id), NOW - 1);
        s1[0] = _sign(K2, nft.hashIntent(one[0]));
        vm.expectRevert(AgentOnlyNFT.Expired.selector);
        nft.execute(id, b, one, s1);
    }

    function test_MintReplayRejected() public {
        AgentOnlyNFT.Terms memory t = AgentOnlyNFT.Terms(AgentOnlyNFT.Op.Mint, bytes32(uint256(7)), 0, 0, 0);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _one(K1, t, 0, 1);
        nft.execute{value: FEE}(0, t, its, sigs);
        vm.expectRevert(AgentOnlyNFT.BadNonce.selector);
        nft.execute{value: FEE}(0, t, its, sigs);
        assertEq(nft.balanceOf(nft.holderAddress(1)), 1);
    }

    // ------------------------------------------------------------ verrou

    function test_LockedTokenCannotMove() public {
        uint256 id = _mint(K1, 1);
        _exec1(K1, _t(AgentOnlyNFT.Op.Lock, 0, 0, NOW + 500), id, 1);

        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(K1, 1, K2, 2, _s(AgentOnlyNFT.Op.Transfer), id);
        vm.expectRevert(AgentOnlyNFT.TokenLocked.selector);
        nft.execute(id, _s(AgentOnlyNFT.Op.Transfer), its, sigs);

        (its, sigs) = _one(K1, _s(AgentOnlyNFT.Op.Burn), id, 1);
        vm.expectRevert(AgentOnlyNFT.TokenLocked.selector);
        nft.execute(id, _s(AgentOnlyNFT.Op.Burn), its, sigs);

        (its, sigs) = _two(K1, 1, K2, 2, _t(AgentOnlyNFT.Op.Lock, 1, 2, NOW + 600), id);
        vm.expectRevert(AgentOnlyNFT.TokenLocked.selector);
        nft.execute(id, _t(AgentOnlyNFT.Op.Lock, 1, 2, NOW + 600), its, sigs);

        // Un verrou personnel ne peut pas etre saisi.
        vm.warp(NOW + 501);
        (its, sigs) = _one(K1, _s(AgentOnlyNFT.Op.Claim), id, 1);
        vm.expectRevert(AgentOnlyNFT.NotLocked.selector);
        nft.execute(id, _s(AgentOnlyNFT.Op.Claim), its, sigs);
    }

    function test_PledgeRulesAndNoDeadlock() public {
        uint256 id = _mint(K1, 1);
        _exec2(K1, 1, K2, 2, _t(AgentOnlyNFT.Op.Lock, 200, 220, NOW + 100), id);
        vm.warp(NOW + 500);

        // L'emprunteur ne peut pas saisir son propre gage.
        AgentOnlyNFT.Terms memory c = _s(AgentOnlyNFT.Op.Claim);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _one(K1, c, id, 1);
        vm.expectRevert(AgentOnlyNFT.NotLocker.selector);
        nft.execute(id, c, its, sigs);

        // Preteur gele apres l'echeance : il ne peut pas saisir, mais le token n'est pas bloque.
        vm.prank(SPONSOR2);
        reg.setFrozen(2, true);
        (its, sigs) = _one(K2, c, id, 2);
        vm.expectRevert(AgentOnlyNFT.NotAgent.selector);
        nft.execute(id, c, its, sigs);
        _exec1(K1, _s(AgentOnlyNFT.Op.Unlock), id, 1);
        (uint256 locker,,) = nft.lockOf(id);
        assertEq(locker, 0);
        assertEq(nft.vaultBalance(1), 980);
        assertEq(nft.vaultBalance(2), 1_020);
        vm.prank(SPONSOR2);
        reg.setFrozen(2, false);

        // Le preteur peut aussi lever le gage lui-meme, sans paiement.
        _exec2(K1, 1, K2, 2, _t(AgentOnlyNFT.Op.Lock, 50, 60, NOW + 900), id);
        _exec1(K2, _s(AgentOnlyNFT.Op.Unlock), id, 2);
        (locker,,) = nft.lockOf(id);
        assertEq(locker, 0);
        assertEq(nft.vaultBalance(1), 1_030);
    }

    function test_FailedPaymentMovesNothing() public {
        uint256 id = _mint(K1, 1);
        AgentOnlyNFT.Terms memory t = _t(AgentOnlyNFT.Op.Transfer, 5_000, 0, 0);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(K1, 1, K2, 2, t, id);
        vm.expectRevert(AgentOnlyNFTWithVault.InsufficientFunds.selector);
        nft.execute(id, t, its, sigs);
        assertEq(nft.agentOf(id), 1);
        assertEq(nft.nonceOf(id), 1);
        assertEq(nft.vaultBalance(2), 1_000);
    }

    // ------------------------------------------------------------ cles et sponsor

    function test_OldAndExpiredKeysRejected() public {
        uint256 id = _mint(K1, 1);
        uint256 k1b = 0x0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b;
        _enroll(SPONSOR1, 1, vm.addr(k1b), 0);

        AgentOnlyNFT.Terms memory t = _s(AgentOnlyNFT.Op.Burn);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _one(K1, t, id, 1);
        vm.expectRevert(AgentOnlyNFT.BadSigner.selector);
        nft.execute(id, t, its, sigs);

        // Passe la duree de validite, meme la bonne cle ne signe plus.
        (its, sigs) = _one(k1b, t, id, 1);
        vm.warp(NOW + TTL);
        vm.expectRevert(AgentOnlyNFT.NotAgent.selector);
        nft.execute(id, t, its, sigs);
        // Le token est toujours rattache a l'agent : un nouvel enrolement lui rend la main.
        assertEq(nft.agentOf(id), 1);
        _enroll(SPONSOR1, 1, vm.addr(K1), 0);
        _exec1(K1, t, id, 1);
    }

    function test_SponsorPowersAreLimited() public {
        uint256 id = _mint(K1, 1);

        vm.prank(address(0x66));
        vm.expectRevert(AgentOnlyNFTWithVault.NotSponsor.selector);
        nft.withdraw(1, 10);
        vm.prank(SPONSOR1);
        nft.withdraw(1, 10);
        assertEq(usdc.balanceOf(SPONSOR1), 10);

        vm.prank(address(0x66));
        vm.expectRevert(AttestedAgentRegistry.NotSponsor.selector);
        reg.setFrozen(1, true);

        vm.prank(SPONSOR1);
        reg.setFrozen(1, true);
        AgentOnlyNFT.Terms memory t = _s(AgentOnlyNFT.Op.Transfer);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(K1, 1, K2, 2, t, id);
        vm.expectRevert(AgentOnlyNFT.NotAgent.selector);
        nft.execute(id, t, its, sigs);
        assertEq(nft.agentOf(id), 1);
    }

    // ------------------------------------------------------------ anti-spam

    function test_MintFeeAndQuota() public {
        AgentOnlyNFT.Terms memory t = AgentOnlyNFT.Terms(AgentOnlyNFT.Op.Mint, bytes32(uint256(7)), 0, 0, 0);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _one(K1, t, 0, 1);
        vm.expectRevert(AgentOnlyNFT.BadFee.selector);
        nft.execute(0, t, its, sigs);

        _mint(K1, 1);
        _mint(K1, 1);
        _mint(K1, 1);
        (its, sigs) = _one(K1, t, 0, 1);
        vm.expectRevert(AgentOnlyNFT.QuotaExceeded.selector);
        nft.execute{value: FEE}(0, t, its, sigs);

        // Le quota d'un agent ne touche pas les autres, et se recharge a la periode suivante.
        _mint(K2, 2);
        vm.warp(NOW + 1 days);
        _mint(K1, 1);
        assertEq(FEES.balance, 5 * FEE);
    }

    // ------------------------------------------------------------ registre

    function test_EnrollmentNeedsThresholdOfAttesters() public {
        address key = vm.addr(HUMAN);
        bytes32 d = _enrollDigest(address(this), 9, key);

        bytes[] memory one = new bytes[](1);
        one[0] = _sign(A1, d);
        vm.expectRevert(AttestedAgentRegistry.NotEnoughAttesters.selector);
        reg.enroll{value: BOND}(9, key, keccak256("preuve"), FAR, one);

        bytes[] memory dup = new bytes[](2);
        dup[0] = _sign(A1, d);
        dup[1] = _sign(A1, d);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll{value: BOND}(9, key, keccak256("preuve"), FAR, dup);

        // Un humain qui signe lui-meme son enrolement n'est pas un attesteur.
        bytes[] memory fake = _attest(A1, HUMAN, d);
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll{value: BOND}(9, key, keccak256("preuve"), FAR, fake);

        bytes[] memory good = _attest(A2, A3, d);
        vm.expectRevert(AttestedAgentRegistry.BadBond.selector);
        reg.enroll(9, key, keccak256("preuve"), FAR, good);

        // Une attestation emise pour un sponsor ne sert pas a un autre.
        vm.deal(address(0x66), 1 ether);
        vm.prank(address(0x66));
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll{value: BOND}(9, key, keccak256("preuve"), FAR, good);

        reg.enroll{value: BOND}(9, key, keccak256("preuve"), FAR, good);
        assertEq(reg.keyOf(9), key);
        // Les memes signatures ne se rejouent pas.
        vm.expectRevert(AttestedAgentRegistry.BadAttester.selector);
        reg.enroll(9, key, keccak256("preuve"), FAR, good);
    }

    function test_RevokeAndRetire() public {
        // Revocation par deux attesteurs : l'agent s'eteint, la caution reste au registre.
        bytes[] memory sigs = _attest(A1, A3, reg.hashRevocation(1));
        reg.revoke(1, sigs);
        assertEq(reg.keyOf(1), address(0));
        vm.prank(SPONSOR1);
        vm.expectRevert(AttestedAgentRegistry.Closed.selector);
        reg.retire(1);
        assertEq(address(reg).balance, 2 * BOND);

        // Retrait volontaire : le sponsor recupere sa caution.
        uint256 before = SPONSOR2.balance;
        vm.prank(SPONSOR2);
        reg.retire(2);
        assertEq(SPONSOR2.balance, before + BOND);
        assertEq(reg.keyOf(2), address(0));
    }

    // ------------------------------------------------------------ coeur seul, sans coffre

    function test_CoreAloneRejectsPayments() public {
        AgentOnlyNFT core = new AgentOnlyNFT(IAgentRegistry(address(reg)), 0, address(0), 3, 1 days);
        AgentOnlyNFT.Terms memory m = AgentOnlyNFT.Terms(AgentOnlyNFT.Op.Mint, bytes32(uint256(7)), 0, 0, 0);
        AgentOnlyNFT.Intent[] memory its = new AgentOnlyNFT.Intent[](1);
        bytes[] memory sigs = new bytes[](1);
        its[0] = AgentOnlyNFT.Intent(uint8(m.op), 0, 1, 0, core.termsHash(m), 0, FAR);
        sigs[0] = _sign(K1, core.hashIntent(its[0]));
        uint256 id = core.execute(0, m, its, sigs);

        AgentOnlyNFT.Terms memory t = _t(AgentOnlyNFT.Op.Transfer, 100, 0, 0);
        its = new AgentOnlyNFT.Intent[](2);
        sigs = new bytes[](2);
        its[0] = AgentOnlyNFT.Intent(uint8(t.op), id, 1, 2, core.termsHash(t), 1, FAR);
        its[1] = AgentOnlyNFT.Intent(uint8(t.op), id, 2, 1, core.termsHash(t), 1, FAR);
        sigs[0] = _sign(K1, core.hashIntent(its[0]));
        sigs[1] = _sign(K2, core.hashIntent(its[1]));
        vm.expectRevert(AgentOnlyNFT.PaymentsDisabled.selector);
        core.execute(id, t, its, sigs);

        // Une intention signee pour un contrat ne vaut pas pour un autre.
        (AgentOnlyNFT.Intent[] memory x, bytes[] memory xs) = _one(K1, m, 0, 1);
        vm.expectRevert(AgentOnlyNFT.BadNonce.selector);
        core.execute(0, m, x, xs);
    }

    // ------------------------------------------------------------ fuzzing

    function testFuzz_RelayerCannotChangePrice(uint128 signedPrice, uint128 shownPrice) public {
        vm.assume(signedPrice != shownPrice);
        uint256 id = _mint(K1, 1);
        AgentOnlyNFT.Terms memory t = _t(AgentOnlyNFT.Op.Transfer, signedPrice, 0, 0);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(K1, 1, K2, 2, t, id);
        vm.expectRevert(AgentOnlyNFT.TermsMismatch.selector);
        nft.execute(id, _t(AgentOnlyNFT.Op.Transfer, shownPrice, 0, 0), its, sigs);
    }

    function testFuzz_RandomKeyCannotMoveToken(uint256 pk) public {
        pk = bound(pk, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140);
        vm.assume(pk != K1);
        uint256 id = _mint(K1, 1);
        AgentOnlyNFT.Terms memory t = _s(AgentOnlyNFT.Op.Transfer);
        (AgentOnlyNFT.Intent[] memory its, bytes[] memory sigs) = _two(pk, 1, K2, 2, t, id);
        vm.expectRevert(AgentOnlyNFT.BadSigner.selector);
        nft.execute(id, t, its, sigs);
    }
}
