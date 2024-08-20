// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @notice Mock implementation of IEmissionReceiver for testing purposes.
 * Why not use a real implementation, like ConvexDepositToken, CurveDepositToken, or TroveManager?
 * Because we don't aim for integration testing, but rather unit testing here,
 * but at a later stage we can aim for integration testing.
 */
contract MockEmissionReceiver {
    bool public notifyRegisteredIdCalled;
    uint256[] public lastAssignedIds;

    function notifyRegisteredId(uint256[] memory assignedIds) external returns (bool) {
        notifyRegisteredIdCalled = true;
        lastAssignedIds = assignedIds;
        return true;
    }

    /**
     * @notice Asserts that notifyRegisteredId was called with the expected number of assigned IDs
     * @dev Added this for testing purposes
     * @param expectedCount The expected number of assigned IDs
     */
    function assertNotifyRegisteredIdCalled(uint256 expectedCount) external view {
        require(notifyRegisteredIdCalled, "notifyRegisteredId was not called");
        require(lastAssignedIds.length == expectedCount, "Unexpected number of assigned IDs");
    }
}
