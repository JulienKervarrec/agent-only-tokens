// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title SHA-384 (FIPS 180-4), for replaying TDX measurement registers on-chain.
/// @notice Unaudited draft. The EVM has no SHA-384 precompile. The 80 rounds are written in
/// assembly for cost; the result is checked against reference vectors and a real dstack log.
library Sha384 {
    // The 80 round constants of SHA-512, 8 bytes each.
    bytes private constant K =
        hex"428a2f98d728ae227137449123ef65cdb5c0fbcfec4d3b2fe9b5dba58189dbbc3956c25bf348b53859f111f1b605d019923f82a4af194f9bab1c5ed5da6d8118d807aa98a303024212835b0145706fbe243185be4ee4b28c550c7dc3d5ffb4e272be5d74f27b896f80deb1fe3b1696b19bdc06a725c71235c19bf174cf692694e49b69c19ef14ad2efbe4786384f25e30fc19dc68b8cd5b5240ca1cc77ac9c652de92c6f592b02754a7484aa6ea6e4835cb0a9dcbd41fbd476f988da831153b5983e5152ee66dfaba831c66d2db43210b00327c898fb213fbf597fc7beef0ee4c6e00bf33da88fc2d5a79147930aa72506ca6351e003826f142929670a0e6e7027b70a8546d22ffc2e1b21385c26c9264d2c6dfc5ac42aed53380d139d95b3df650a73548baf63de766a0abb3c77b2a881c2c92e47edaee692722c851482353ba2bfe8a14cf10364a81a664bbc423001c24b8b70d0f89791c76c51a30654be30d192e819d6ef5218d69906245565a910f40e35855771202a106aa07032bbd1b819a4c116b8d2d0c81e376c085141ab532748774cdf8eeb9934b0bcb5e19b48a8391c0cb3c5c95a634ed8aa4ae3418acb5b9cca4f7763e373682e6ff3d6b2b8a3748f82ee5defb2fc78a5636f43172f6084c87814a1f0ab728cc702081a6439ec90befffa23631e28a4506cebde82bde9bef9a3f7b2c67915c67178f2e372532bca273eceea26619cd186b8c721c0c207eada7dd6cde0eb1ef57d4f7fee6ed17806f067aa72176fba0a637dc5a2c898a6113f9804bef90dae1b710b35131c471b28db77f523047d8432caab7b40c724933c9ebe0a15c9bebc431d67c49c100d4c4cc5d4becb3e42b6597f299cfc657e2a5fcb6fab3ad6faec6c44198c4a475817";

    /// Returns the 48-byte digest as its first 32 bytes and its last 16 bytes.
    function hash(bytes memory data) internal pure returns (bytes32 high, bytes16 low) {
        uint64[8] memory h = [
            0xcbbb9d5dc1059ed8,
            0x629a292a367cd507,
            0x9159015a3070dd17,
            0x152fecd8f70e5939,
            0x67332667ffc00b31,
            0x8eb44a8768581511,
            0xdb0c2e0d64f98fa7,
            0x47b5481dbefa4fa4
        ];
        // Padding: 0x80, zeros, then the length in bits on 16 bytes; total a multiple of 128.
        uint256 length = data.length;
        uint256 zeros = 127 - ((length + 16) % 128);
        bytes memory message = abi.encodePacked(data, bytes1(0x80), new bytes(zeros), uint128(length * 8));

        bytes memory k = K;
        for (uint256 offset; offset < message.length; offset += 128) {
            _block(h, message, offset, k);
        }
        high = bytes32((uint256(h[0]) << 192) | (uint256(h[1]) << 128) | (uint256(h[2]) << 64) | uint256(h[3]));
        low = bytes16((uint128(h[4]) << 64) | uint128(h[5]));
    }

    /// Processes one 128-byte block of `message` at `offset` into the state `h`.
    function _block(uint64[8] memory h, bytes memory message, uint256 offset, bytes memory k) private pure {
        assembly ("memory-safe") {
            let mask := 0xffffffffffffffff
            function rotr(x, n) -> r {
                r := and(or(shr(n, x), shl(sub(64, n), x)), 0xffffffffffffffff)
            }
            // Message schedule: 80 words of 64 bits, one per 32-byte memory slot.
            let w := mload(0x40)
            let src := add(add(message, 0x20), offset)
            for { let t := 0 } lt(t, 16) { t := add(t, 1) } {
                mstore(add(w, shl(5, t)), shr(192, mload(add(src, shl(3, t)))))
            }
            for { let t := 16 } lt(t, 80) { t := add(t, 1) } {
                let x := mload(add(w, shl(5, sub(t, 15))))
                let y := mload(add(w, shl(5, sub(t, 2))))
                let s0 := xor(xor(rotr(x, 1), rotr(x, 8)), shr(7, x))
                let s1 := xor(xor(rotr(y, 19), rotr(y, 61)), shr(6, y))
                let sum := add(add(mload(add(w, shl(5, sub(t, 16)))), s0), add(mload(add(w, shl(5, sub(t, 7)))), s1))
                mstore(add(w, shl(5, t)), and(sum, mask))
            }
            // Working variables are kept in memory too, to stay within the stack limit.
            let v := add(w, 2560)
            for { let i := 0 } lt(i, 8) { i := add(i, 1) } {
                mstore(add(v, shl(5, i)), mload(add(h, shl(5, i))))
            }
            let kp := add(k, 0x20)
            for { let t := 0 } lt(t, 80) { t := add(t, 1) } {
                let e := mload(add(v, 128))
                let a := mload(v)
                let ch := xor(and(e, mload(add(v, 160))), and(xor(e, mask), mload(add(v, 192))))
                let t1 :=
                    add(
                        add(mload(add(v, 224)), xor(xor(rotr(e, 14), rotr(e, 18)), rotr(e, 41))),
                        add(add(ch, shr(192, mload(add(kp, shl(3, t))))), mload(add(w, shl(5, t))))
                    )
                let b := mload(add(v, 32))
                let c := mload(add(v, 64))
                let maj := xor(xor(and(a, b), and(a, c)), and(b, c))
                let t2 := add(xor(xor(rotr(a, 28), rotr(a, 34)), rotr(a, 39)), maj)
                mstore(add(v, 224), mload(add(v, 192))) // h = g
                mstore(add(v, 192), mload(add(v, 160))) // g = f
                mstore(add(v, 160), e) // f = e
                mstore(add(v, 128), and(add(mload(add(v, 96)), t1), mask)) // e = d + t1
                mstore(add(v, 96), c) // d = c
                mstore(add(v, 64), b) // c = b
                mstore(add(v, 32), a) // b = a
                mstore(v, and(add(t1, t2), mask)) // a = t1 + t2
            }
            for { let i := 0 } lt(i, 8) { i := add(i, 1) } {
                let p := add(h, shl(5, i))
                mstore(p, and(add(mload(p), mload(add(v, shl(5, i)))), mask))
            }
        }
    }
}
