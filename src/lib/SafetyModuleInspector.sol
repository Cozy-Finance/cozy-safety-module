// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {ReservePool} from "./structs/Pools.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract SafetyModuleInspector is SafetyModuleCommon {
  function convertToReceiptTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    depositReceiptTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_,
      reservePool_.depositReceiptToken.totalSupply(),
      reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount
    );
  }

  function convertToReserveAssetAmount(uint256 reservePoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    uint256 totalPoolAmount_ = reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount;
    uint256 nextTotalPoolAmount_ = totalPoolAmount_
      - _getNextDripAmount(
        totalPoolAmount_,
        cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))),
        reservePool_.lastFeesDripTime
      );

    reserveAssetAmount_ = nextTotalPoolAmount_ == 0
      ? 0
      : SafetyModuleCalculationsLib.convertToAssetAmount(
        depositReceiptTokenAmount_, reservePool_.depositReceiptToken.totalSupply(), nextTotalPoolAmount_
      );
  }
}
