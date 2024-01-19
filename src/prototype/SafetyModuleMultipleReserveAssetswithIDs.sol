// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {IReceiptToken as IStkAsset} from "../interfaces/IReceiptToken.sol";

/// @dev Multiple asset SafetyModule.
contract SafetyModule {
  struct RewardPool {
    uint128 amount;
    IDripModel dripModel;
    uint128 lastDripTime;
  }

  struct ClaimedRewards {
    IERC20 asset;
    uint128 amount;
  }

  /// @dev reserveAsset index in this array is its ID
  IERC20[] public reserveAssets;

  uint256[] public reserveAssetPools;

  /// @dev rewardAsset index in this array is its ID
  IERC20[] public claimableRewardAssets;

  mapping(IERC20 asset_ => uint256 amount_) public claimableRewardPools;

  mapping(IERC20 asset_ => RewardPool rewardPool_) public undrippedRewardPools;

  mapping(IStkAsset asset_ => uint256 reserveAssetPoolId) public stkAssetToReserveAssetPoolId;

  /// @dev stkAsset index in this array is its ID
  IStkAsset[] public stkAssets;

  /// @dev The weighting of each stkAsset's claim to all reward pools. Must sum to 1.
  /// e.g. stkAssetA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkAssetA
  /// wrt totalSupply.
  uint16[] public stkAssetRewardPoolWeights;

  /// @dev Delay before a staker and unstake
  uint128 public unstakeDelay;

  /// @dev Has config for deposit fee and where to send fees
  address public cozyFeeManager;

  /// @dev Expects `from_` to have approved this SafetyModule for `amount_` of `reserveAssets[assetId_]` so it can
  /// `transferFrom`
  function depositReserveAssets(uint16 assetId_, address from_, uint256 amount_) external {}

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint16 assetId_, address from_, uint256 amount_) external {}

  /// @dev Rewards can be any token (not necessarily the same as the reserve asset)
  function depositRewardsAssets(uint16 assetId_, address from_, uint256 amount_) external {}

  /// @dev Helpful in cases where depositing reserve and rewards asset in single transfer (same token)
  function deposit(
    uint16 assetId_,
    address from_,
    uint256 amount_,
    uint256 rewardsPercentage_,
    uint256 reservePercentage_
  ) external {}

  function stake(uint16 assetId_, uint256 amount_, address receiver_, address from_)
    external
    returns (uint256 stkAssetAmount_)
  {}

  function stakeWithoutTransfer(uint16 assetId_, uint256 amount_, address receiver_)
    external
    returns (uint256 stkAssetAmount_)
  {}

  function unStake(uint16 assetId_, uint256 amount_, address receiver_, address from_)
    external
    returns (uint256 reserveAssetAmount_)
  {}

  function unStakeWithoutTransfer(uint16 assetId_, uint256 amount_, address receiver_)
    external
    returns (uint256 reserveAssetAmount_)
  {}

  function claimRewards(address owner_) external returns (ClaimedRewards[] memory claimedRewards_) {}
}
