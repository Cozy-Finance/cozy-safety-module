// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {ReservePool} from "./structs/Pools.sol";

abstract contract SafetyModuleInspector is SafetyModuleCommon {
  function convertToReserveDepositTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 depositTokenAmount_)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    depositTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_,
      reservePool_.depositToken.totalSupply(),
      reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount
    );
  }

  function convertReserveDepositTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    reserveAssetAmount_ = SafetyModuleCalculationsLib.convertToAssetAmount(
      depositTokenAmount_,
      reservePool_.depositToken.totalSupply(),
      reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount
    );
  }
}
