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

  function convertToRewardDepositTokenAmount(uint256 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositTokenAmount_)
  {
    depositTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      rewardAssetAmount_,
      rewardPools[rewardPoolId_].depositToken.totalSupply(),
      rewardPools[rewardPoolId_].undrippedRewards
    );
  }

  function convertToStakeTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 stakeTokenAmount_)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    stakeTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_,
      reservePool_.stkToken.totalSupply(),
      reservePool_.stakeAmount - reservePool_.pendingUnstakesAmount
    );
  }

  function convertStakeTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 stakeTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_)
  {
    ReservePool memory reservePool_ = reservePools[reservePoolId_];
    reserveAssetAmount_ = SafetyModuleCalculationsLib.convertToAssetAmount(
      stakeTokenAmount_,
      reservePool_.stkToken.totalSupply(),
      reservePool_.stakeAmount - reservePool_.pendingUnstakesAmount
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

  function convertRewardDepositTokenToRewardAssetAmount(uint256 rewardPoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_)
  {
    rewardAssetAmount_ = SafetyModuleCalculationsLib.convertToAssetAmount(
      depositTokenAmount_,
      rewardPools[rewardPoolId_].depositToken.totalSupply(),
      rewardPools[rewardPoolId_].undrippedRewards
    );
  }
}
