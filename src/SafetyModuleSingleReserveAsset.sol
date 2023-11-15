// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {IRewardsDripModel} from "./interfaces/IRewardsDripModel.sol";

/// @dev Single asset safety module. Is an LFT.
contract SafetyModule {
  struct UndrippedRewardPool {
    uint128 amount;
    IRewardsDripModel dripModel;
    uint128 lastDripTime;
  }

  struct ClaimedRewards {
    IERC20 asset;
    uint128 amount;
  }

  IERC20 public reserveAsset;

  uint256 public reserveAssetPool;

  IERC20[] public claimableRewardAssets;

  mapping(IERC20 asset_ => uint256 amount_) public claimableRewardPools;

  mapping(IERC20 asset_ => UndrippedRewardPool undrippedRewardPool_) public undrippedRewardPools;

  /// @dev Delay before a staker and unstake
  uint128 public unstakeDelay;

  /// @dev Has config for deposit fee and where to send fees
  address public cozyFeeManager;

  /// @dev Expects `from_` to have approved this SafetyModule for `amount_` of `reserveAsset` so it can `transferFrom`
  function depositReserveAssets(address from_, uint256 amount_) external {}

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(address from_, uint256 amount_) external {}

  /// @dev Rewards can be any token (not necessarily the same as the reserve asset)
  function depositRewardsAssets(IERC20 asset_, address from_, uint256 amount_) external {}

  /// @dev Helpful in cases where depositing reserve and rewards asset in single transfer (same token)
  function deposit(
    IERC20 asset_,
    address from_,
    uint256 amount_,
    uint256 rewardsPercentage_,
    uint256 reservePercentage_
  ) external {}

  function stake(uint256 amount_, address receiver_, address from_) external returns (uint256 stkAssetAmount_) {}

  function stakeWithoutTransfer(uint256 amount_, address receiver_) external returns (uint256 stkAssetAmount_) {}

  function unStake(uint256 amount_, address receiver_, address from_) external returns (uint256 reserveAssetAmount_) {}

  function unStakeWithoutTransfer(uint256 amount_, address receiver_) external returns (uint256 reserveAssetAmount_) {}

  function claimRewards(address owner_) external returns (ClaimedRewards[] memory claimedRewards_) {}
}
