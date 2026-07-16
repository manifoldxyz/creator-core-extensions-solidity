// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CXRDSTestBase} from "./CXRDSTestBase.t.sol";

/**
 * @title  CXRDSPacksSize
 * @notice US-011 — EIP-170 runtime-size assertion (AC-12 size leg).
 *
 *         Reads the REAL deployed runtime bytecode length of the CXRDSPacks
 *         instance deployed by CXRDSTestBase and asserts it is strictly below the
 *         EIP-170 contract-size limit of 24,576 bytes. Size is solved as a single
 *         contract (~18,872 B, ~5,704 B headroom) — no companion split is taken.
 *         This test is the guardrail that fails loudly if NatSpec/OZ EIP712 or
 *         future changes ever push the runtime over the limit.
 */
contract CXRDSPacksSize is CXRDSTestBase {
    /// @notice EIP-170 maximum contract runtime bytecode size in bytes.
    uint256 internal constant EIP170_MAX_CODE_SIZE = 24576;

    function test_runtimeBytecodeUnderEIP170() public {
        uint256 codeSize = address(cxrds).code.length;

        assertGt(codeSize, 0, "cxrds runtime bytecode present");
        assertLt(
            codeSize,
            EIP170_MAX_CODE_SIZE,
            "CXRDSPacks runtime bytecode must be < 24576 B (EIP-170)"
        );

        // Informational log so the actual size and headroom show under -vv.
        emit log_named_uint("cxrds runtime code size (bytes)", codeSize);
        emit log_named_uint("EIP-170 headroom (bytes)", EIP170_MAX_CODE_SIZE - codeSize);
    }
}
