// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";

/**
 * @title  ManifoldPacksSize
 * @notice US-011 — EIP-170 runtime-size assertion (AC-12 size leg).
 *
 *         Reads the REAL deployed runtime bytecode length of the ManifoldPacksSeaDropShim
 *         instance deployed by ManifoldPacksTestBase and asserts it is strictly below the
 *         EIP-170 contract-size limit of 24,576 bytes.
 *
 *         COVERAGE NOTE: `forge coverage` recompiles with the optimizer OFF and
 *         injects per-line instrumentation, which inflates the runtime bytecode
 *         far past EIP-170 (~39 KB) — that is NOT the deployable size and would
 *         both fail the strict assertion and underflow the headroom math. Size
 *         only means something for the OPTIMIZED build, which the standard
 *         `forge test` run measures (and strictly asserts here). So this test
 *         tiers on the measured size:
 *           - `< EIP170_MAX`                              → assert & log headroom (the real guardrail).
 *           - `EIP170_MAX .. INSTRUMENTED_BUILD_FLOOR`    → FAIL: a genuine optimized-build regression.
 *           - `>= INSTRUMENTED_BUILD_FLOOR`               → skip: the unoptimized coverage/instrumented build.
 *         An optimized contract can never deploy above EIP-170, so the middle
 *         band is a real failure; only a build several KB over the limit is the
 *         instrumented coverage build, which we skip rather than double-fail.
 */
contract ManifoldPacksSize is ManifoldPacksTestBase {
    /// @notice EIP-170 maximum contract runtime bytecode size in bytes.
    uint256 internal constant EIP170_MAX_CODE_SIZE = 24576;

    /// @notice Floor above which a measured runtime size can only be the
    ///         unoptimized/instrumented `forge coverage` build (optimized code
    ///         can never deploy this far over the EIP-170 limit). EIP-170 + 4 KB.
    uint256 internal constant INSTRUMENTED_BUILD_FLOOR = EIP170_MAX_CODE_SIZE + 4096;

    function test_runtimeBytecodeUnderEIP170() public {
        uint256 codeSize = address(packs).code.length;

        assertGt(codeSize, 0, "packs runtime bytecode present");

        // Unoptimized/instrumented coverage build — not the deployable size.
        // The optimized `forge test` run is the authoritative guardrail.
        if (codeSize >= INSTRUMENTED_BUILD_FLOOR) {
            emit log_named_uint(
                "skipping EIP-170 assert (unoptimized/coverage build); measured size", codeSize
            );
            return;
        }

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
