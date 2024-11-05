// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface IWithdrawLimitModule {
    function available_withdraw_limit(
        address owner,
        uint256 maxLoss,
        address[] calldata strategies
    ) external view returns (uint256);
}
