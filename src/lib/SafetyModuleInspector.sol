// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {ReservePool} from "./structs/Pools.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract SafetyModuleInspector is SafetyModuleCommon {
  /// @notice Returns the receipt token amount for a given amount of reserve assets after taking into account
  /// any pending fee drip.
  /// @param reservePoolId_ The ID of the reserve pool to convert the reserve asset amount for.
  /// @param reserveAssetAmount_ The amount of reserve assets to convert to deposit receipt tokens.
  function convertToReceiptTokenAmount(uint8 reservePoolId_, uint256 reserveAssetAmount_)
    public
    view
    override
    returns (uint256)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    uint256 nextTotalPoolAmount_ = _getTotalReservePoolAmountForExchangeRate(reservePool_);
    return SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, reservePool_.depositReceiptToken.totalSupply(), nextTotalPoolAmount_
    );
  }

  /// @notice Returns the reserve asset amount for a given amount of deposit receipt tokens after taking into account
  /// any
  /// pending fee drip.
  /// @param reservePoolId_ The ID of the reserve pool to convert the deposit receipt token amount for.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to convert to reserve assets.
  function convertToReserveAssetAmount(uint8 reservePoolId_, uint256 depositReceiptTokenAmount_)
    public
    view
    override
    returns (uint256)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    uint256 nextTotalPoolAmount_ = _getTotalReservePoolAmountForExchangeRate(reservePool_);
    return SafetyModuleCalculationsLib.convertToAssetAmount(
      depositReceiptTokenAmount_, reservePool_.depositReceiptToken.totalSupply(), nextTotalPoolAmount_
    );
  }

  /// @notice Returns the amount of assets in the reserve pool to be used for exchange rate calculations after taking
  /// into
  /// account any pending fee drip.
  /// @param reservePool_ The reserve pool to target.
  function _getTotalReservePoolAmountForExchangeRate(ReservePool memory reservePool_) internal view returns (uint256) {
    uint256 totalPoolAmount_ = reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount;
    if (safetyModuleState == SafetyModuleState.ACTIVE) {
      return totalPoolAmount_
        - _getNextDripAmount(
          totalPoolAmount_,
          cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))),
          reservePool_.lastFeesDripTime
        );
    } else {
      return totalPoolAmount_;
    }
  }
}
