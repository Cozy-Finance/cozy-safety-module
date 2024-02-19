// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {ReservePool} from "./structs/Pools.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract SafetyModuleInspector is SafetyModuleCommon {
  /// @notice Returns the reserve asset amount for a given amount of deposit receipt tokens after taking into account
  /// any
  /// pending fee drip.
  function convertToReceiptTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    public
    view
    override
    returns (uint256)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];

    uint256 totalPoolAmount_ = reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount;
    uint256 nextTotalPoolAmount_ = totalPoolAmount_
      - _getNextDripAmount(
        totalPoolAmount_,
        cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))),
        reservePool_.lastFeesDripTime
      );

    return SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, reservePool_.depositReceiptToken.totalSupply(), nextTotalPoolAmount_
    );
  }

  // @dev Returns the reserve asset amount for a given amount of deposit receipt tokens after taking into account any
  // pending fee drip.
  function convertToReserveAssetAmount(uint256 reservePoolId_, uint256 depositReceiptTokenAmount_)
    public
    view
    override
    returns (uint256)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    uint256 totalPoolAmount_ = reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount;
    uint256 nextTotalPoolAmount_ = totalPoolAmount_
      - _getNextDripAmount(
        totalPoolAmount_,
        cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))),
        reservePool_.lastFeesDripTime
      );

    return SafetyModuleCalculationsLib.convertToAssetAmount(
      depositReceiptTokenAmount_, reservePool_.depositReceiptToken.totalSupply(), nextTotalPoolAmount_
    );
  }
}
