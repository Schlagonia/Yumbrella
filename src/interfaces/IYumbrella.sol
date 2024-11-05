// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IWithdrawLimitModule} from "./IWithdrawLimitModule.sol";

interface IYumbrella is IStrategy, IBaseHealthCheck, IWithdrawLimitModule {
    //TODO: Add your specific implementation interface in here.
    function available_deposit_limit(address _receiver)
        external
        view
        returns (uint256);
}
