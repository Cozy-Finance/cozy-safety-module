// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {UpdateConfigsCalldataParams} from "../lib/structs/Configs.sol";
import {IDripModel} from "./IDripModel.sol";
import {IReceiptToken} from "./IReceiptToken.sol";
import {UndrippedRewardPoolConfig, ReservePoolConfig} from "../lib/structs/Configs.sol";

interface ISafetyModule {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(address owner_, address pauser_, UpdateConfigsCalldataParams calldata configs_) external;

  function completeRedemption(uint64 redemptionId_) external returns (uint256 assetAmount_);

  function completeUnstake(uint64 redemptionId_) external returns (uint256 reserveAssetAmount_);

  function convertToReserveDepositTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 depositTokenAmount_);

  function convertToRewardDepositTokenAmount(uint256 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositTokenAmount_);

  function convertToStakeTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 stakeTokenAmount_);

  function convertStakeTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 stakeTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_);

  function convertReserveDepositTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_);

  function convertRewardDepositTokenToRewardAssetAmount(uint256 rewardPoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_);

  function depositReserveAssetsWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_);

  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_);

  /// @notice Stake by minting `stkTokenAmount_` stkTokens to `receiver_`.
  /// @dev Assumes that `amount_` of reserve asset has already been transferred to this contract.
  function stakeWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 stkTokenAmount_);

  /// @notice Updates the safety module's user rewards data prior to a stkToken transfer.
  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external;

  /// @notice Pauses the safety module.
  function pause() external;

  /// @notice Redeem by burning `depositTokenAmount_` of `reservePoolId_` reserve pool deposit tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeem(uint16 reservePoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_);

  /// @notice Redeem by burning `depositTokenAmount_` of `rewardPoolId_` reward pool deposit tokens and sending
  /// `rewardAssetAmount_` of `rewardPoolId_` reward pool assets to `receiver_`. Reward pool assets can only be redeemed
  /// if they have not been dripped yet.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeemUndrippedRewards(uint16 rewardPoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 rewardAssetAmount_);

  /// @notice Retrieve accounting and metadata about reserve pools.
  function reservePools(uint256 id_)
    external
    view
    returns (
      uint256 stakeAmount,
      uint256 depositAmount,
      uint256 pendingUnstakesAmount,
      uint256 pendingWithdrawalsAmount,
      uint256 feeAmount,
      /// @dev The max percentage of the stake amount that can be slashed in a SINGLE slash as a WAD. If multiple
      /// slashes
      /// occur, they compound, and the final stake amount can be less than (1 - maxSlashPercentage)% following all the
      /// slashes. The max slash percentage is only a guarantee for stakers; depositors are always at risk to be fully
      /// slashed.
      uint256 maxSlashPercentage,
      IERC20 asset,
      IReceiptToken stkToken,
      IReceiptToken depositToken,
      /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
      /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
      /// wrt totalSupply.
      uint16 rewardsPoolsWeight
    );

  /// @notice Retrieve accounting and metadata about undripped reward pools.
  /// @dev Claimable reward pool IDs are mapped 1:1 with undripped reward pool IDs.
  function undrippedRewardPools(uint256 id_)
    external
    view
    returns (uint256 amount, IERC20 asset, IDripModel dripModel, IReceiptToken depositToken);

  /// @notice Redeem by burning `stkTokenAmount_` of `reservePoolId_` reserve pool stake tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`. Also claims any outstanding rewards
  /// and sends them to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its stake tokens.
  function unstake(uint16 reservePoolId_, uint256 stkTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_);

  /// @notice Unpauses the safety module.
  function unpause() external;

  // @notice Claims the safety module's fees.
  function claimFees(address owner_) external;
}
