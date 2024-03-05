// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";

interface IRewardsManager {
  struct RewardPool {
    // The amount of undripped rewards held by the reward pool.
    uint256 undrippedRewards;
    // The cumulative amount of rewards dripped since the last config update. This value is reset to 0 on each config
    // update.
    uint256 cumulativeDrippedRewards;
    // The last time undripped rewards were dripped from the reward pool.
    uint128 lastDripTime;
    // The underlying asset of the reward pool.
    IERC20 asset;
    // The drip model for the reward pool.
    IDripModel dripModel;
    // The receipt token for the reward pool.
    IReceiptToken depositReceiptToken;
  }

  struct StakePool {
    // The balance of the underlying asset held by the stake pool.
    uint256 amount;
    // The underlying asset of the stake pool.
    IERC20 asset;
    // The receipt token for the stake pool.
    IReceiptToken stkReceiptToken;
    // The weighting of each stake pool's claim to all reward pools in terms of a ZOC. Must sum to ZOC. e.g.
    // stakePoolA.rewardsWeight = 10%, means stake pool A is eligible for up to 10% of rewards dripped from all reward
    // pools.
    uint16 rewardsWeight;
  }

  function convertRewardAssetToReceiptTokenAmount(uint16 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_);

  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
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

  function stake(uint16 stakePoolId_, uint256 assetAmount_, address receiver_, address from_) external;

  function stakeWithoutTransfer(uint16 stakePoolId_, uint256 assetAmount_, address receiver_) external;

  function unstake(uint16 stakePoolId_, uint256 stkReceiptTokenAmount_, address receiver_, address owner_) external;
}
