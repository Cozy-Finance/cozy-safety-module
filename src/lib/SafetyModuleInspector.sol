// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {ReservePool} from "./structs/Pools.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract SafetyModuleInspector is SafetyModuleCommon {
  /// @notice Returns the receipt token amount for a given amount of reserve assets after taking into account
  /// any pending fee drip.
  function convertToReceiptTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
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

  // @dev Returns the reserve asset amount for a given amount of deposit receipt tokens after taking into account any
  // pending fee drip.
  function convertToReserveAssetAmount(uint256 reservePoolId_, uint256 depositReceiptTokenAmount_)
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

  /// @dev Returns the amount of assets in the reserve pool to be used for exchange rate calculations after taking into
  /// account any pending fee drip.
  function _getTotalReservePoolAmountForExchangeRate(ReservePool memory reservePool_) internal view returns (uint256) {
    uint256 totalPoolAmount_ = reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount;
    return totalPoolAmount_
      - _getNextDripAmount(
        totalPoolAmount_,
        cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))),
        reservePool_.lastFeesDripTime
      );
  }
}
