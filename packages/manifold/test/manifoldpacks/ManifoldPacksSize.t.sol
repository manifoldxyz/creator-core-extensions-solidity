// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";

/**
 * @title  ManifoldPacksSize
 * @notice US-011 — EIP-170 runtime-size assertion (AC-12 size leg).
 *
 *         Reads the REAL deployed runtime bytecode length of the ManifoldPacksSeaDropShim
 *         instance deployed by ManifoldPacksTestBase and asserts it is strictly below the
 *         EIP-170 contract-size limit of 24,576 bytes. Size is solved as a single
 *         contract (~18,872 B, ~5,704 B headroom) — no companion split is taken.
 *         This test is the guardrail that fails loudly if NatSpec/OZ EIP712 or
 *         future changes ever push the runtime over the limit.
 */
contract ManifoldPacksSize is ManifoldPacksTestBase {
    /// @notice EIP-170 maximum contract runtime bytecode size in bytes.
    uint256 internal constant EIP170_MAX_CODE_SIZE = 24576;

    function test_runtimeBytecodeUnderEIP170() public {
        uint256 codeSize = address(packs).code.length;

        assertGt(codeSize, 0, "packs runtime bytecode present");
        assertLt(
            codeSize,
            EIP170_MAX_CODE_SIZE,
            "ManifoldPacksSeaDropShim runtime bytecode must be < 24576 B (EIP-170)"
        );

        // Informational log so the actual size and headroom show under -vv.
        emit log_named_uint("packs runtime code size (bytes)", codeSize);
        emit log_named_uint("EIP-170 headroom (bytes)", EIP170_MAX_CODE_SIZE - codeSize);
    }
}
