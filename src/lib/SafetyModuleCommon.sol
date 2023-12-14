// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {SafetyModuleBaseStorage} from "./SafetyModuleBaseStorage.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";

abstract contract SafetyModuleCommon is SafetyModuleBaseStorage, ICommonErrors {
  /// @dev Prepares pending unstakes to have their exchange rates adjusted after a trigger. Defined in `Unstaker`.
  function _updateUnstakesAfterTrigger(uint16 reservePoolId_, uint128 stakeAmount_, uint128 slashAmount_)
    internal
    virtual;
}
