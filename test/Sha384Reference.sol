// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title Plain-Solidity SHA-384, test reference for the assembly version in src/Sha384.sol.
/// @notice Unaudited draft. The EVM has no SHA-384 precompile; this is plain Solidity with a
/// little assembly to read 64-bit words.
library Sha384Reference {
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
        uint64[80] memory w;
        for (uint256 offset; offset < message.length; offset += 128) {
            unchecked {
                for (uint256 t; t < 16; ++t) {
                    w[t] = _word64(message, offset + t * 8);
                }
                for (uint256 t = 16; t < 80; ++t) {
                    uint64 s0 = _rotr(w[t - 15], 1) ^ _rotr(w[t - 15], 8) ^ (w[t - 15] >> 7);
                    uint64 s1 = _rotr(w[t - 2], 19) ^ _rotr(w[t - 2], 61) ^ (w[t - 2] >> 6);
                    w[t] = w[t - 16] + s0 + w[t - 7] + s1;
                }
                _compress(h, w, k);
            }
        }
        high = bytes32((uint256(h[0]) << 192) | (uint256(h[1]) << 128) | (uint256(h[2]) << 64) | uint256(h[3]));
        low = bytes16((uint128(h[4]) << 64) | uint128(h[5]));
    }

    function _compress(uint64[8] memory h, uint64[80] memory w, bytes memory k) private pure {
        uint64 a = h[0];
        uint64 b = h[1];
        uint64 c = h[2];
        uint64 d = h[3];
        uint64 e = h[4];
        uint64 f = h[5];
        uint64 g = h[6];
        uint64 hh = h[7];
        unchecked {
            for (uint256 t; t < 80; ++t) {
                uint64 t1 = hh + (_rotr(e, 14) ^ _rotr(e, 18) ^ _rotr(e, 41)) + ((e & f) ^ (~e & g)) + _word64(k, t * 8) + w[t];
                uint64 t2 = (_rotr(a, 28) ^ _rotr(a, 34) ^ _rotr(a, 39)) + ((a & b) ^ (a & c) ^ (b & c));
                hh = g;
                g = f;
                f = e;
                e = d + t1;
                d = c;
                c = b;
                b = a;
                a = t1 + t2;
            }
            h[0] += a;
            h[1] += b;
            h[2] += c;
            h[3] += d;
            h[4] += e;
            h[5] += f;
            h[6] += g;
            h[7] += hh;
        }
    }

    /// The big-endian 64-bit word at `offset` in `data`. The caller keeps `offset + 8` in range.
    function _word64(bytes memory data, uint256 offset) private pure returns (uint64 word) {
        assembly ("memory-safe") {
            word := shr(192, mload(add(add(data, 0x20), offset)))
        }
    }

    function _rotr(uint64 x, uint64 n) private pure returns (uint64) {
        return (x >> n) | (x << (64 - n));
    }
}
