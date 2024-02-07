// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IDripModel} from "./IDripModel.sol";

interface IRewardsManager {
  struct RewardPool {
    uint256 undrippedRewards;
    /// @dev The cumulative amount of rewards dripped to the pool since the last weight change. This value is reset to 0
    /// anytime rewards weights are updated.
    uint256 cumulativeDrippedRewards;
    uint128 lastDripTime;
    IERC20 asset;
    IDripModel dripModel;
    IReceiptToken depositReceiptToken;
  }

  struct StakePool {
    uint256 amount;
    IERC20 asset;
    IReceiptToken stkReceiptToken;
    /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
    /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
    /// wrt totalSupply.
    uint16 rewardsWeight;
  }

  function convertRewardAssetToReceiptTokenAmount(uint256 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_);

  function convertStakeAssetToReceiptTokenAmount(uint256 stakePoolId_, uint256 stakeAssetAmount_)
    external
    view
    returns (uint256 stakeReceiptTokenAmount_);

  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  function redeemUndrippedRewards(
    uint16 rewardPoolId_,
    uint256 depositReceiptTokenAmount_,
    address receiver_,
    address owner_
  ) external returns (uint256 rewardAssetAmount_);

  function rewardPools(uint256 id_) external view returns (RewardPool memory rewardPool_);

  function stakePools(uint256 id_) external view returns (RewardPool memory stakePool_);

  function stake(uint16 stakePoolId_, uint256 assetAmount_, address receiver_, address from_)
    external
    returns (uint256 stkReceiptTokenAmount_);

  function stakeWithoutTransfer(uint16 stakePoolId_, uint256 assetAmount_, address receiver_)
    external
    returns (uint256 stkReceiptTokenAmount_);

  function unstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 assetAmount_);
}
