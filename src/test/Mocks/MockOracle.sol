// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IOracle} from "../../interfaces/IOracle.sol";

contract MockOracle is IOracle {
    function getRate() external view returns (uint256) {
        return 1e18;
    }
}
