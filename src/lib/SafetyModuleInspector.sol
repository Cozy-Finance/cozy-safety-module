// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";

abstract contract SafetyModuleInspector is SafetyModuleCommon {
  function convertToReserveDepositTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 depositTokenAmount_)
  {
    depositTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_,
      reservePools[reservePoolId_].depositToken.totalSupply(),
      reservePools[reservePoolId_].depositAmount
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
    stakeTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, reservePools[reservePoolId_].stkToken.totalSupply(), reservePools[reservePoolId_].stakeAmount
    );
  }

  function convertStakeTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 stakeTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_)
  {
    reserveAssetAmount_ = SafetyModuleCalculationsLib.convertToAssetAmount(
      stakeTokenAmount_, reservePools[reservePoolId_].stkToken.totalSupply(), reservePools[reservePoolId_].stakeAmount
    );
  }

  function convertReserveDepositTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_)
  {
    reserveAssetAmount_ = SafetyModuleCalculationsLib.convertToAssetAmount(
      depositTokenAmount_,
      reservePools[reservePoolId_].depositToken.totalSupply(),
      reservePools[reservePoolId_].depositAmount
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
