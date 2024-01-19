// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IDripModel} from "../../interfaces/IDripModel.sol";
import {IReceiptToken} from "../../interfaces/IReceiptToken.sol";

struct AssetPool {
  // The total balance of assets held by a SafetyModule, should be equivalent to
  // token.balanceOf(address(this)), discounting any assets directly sent
  // to the SafetyModule via direct transfer.
  uint256 amount;
}

struct ReservePool {
  uint256 stakeAmount;
  uint256 depositAmount;
  uint256 pendingUnstakesAmount;
  uint256 pendingWithdrawalsAmount;
  uint256 feeAmount;
  /// @dev The max percentage of the stake amount that can be slashed in a SINGLE slash as a WAD. If multiple slashes
  /// occur, they compound, and the final stake amount can be less than (1 - maxSlashPercentage)% following all the
  /// slashes. The max slash percentage is only a guarantee for stakers; depositors are always at risk to be fully
  /// slashed.
  uint256 maxSlashPercentage;
  IERC20 asset;
  IReceiptToken stkToken;
  IReceiptToken depositToken;
  /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
  /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
  /// wrt totalSupply.
  uint16 rewardsPoolsWeight;
  uint128 lastFeesDripTime;
}

struct RewardPool {
  uint256 amount;
  /// @dev The cumulative amount of rewards dripped to the pool since the last weight change. On a call to
  /// `finalizeConfigUpdates`, if the associated config update changes the rewards weights, this value is reset to 0.
  uint256 cumulativeDrippedRewards;
  uint128 lastDripTime;
  IERC20 asset;
  IDripModel dripModel;
  IReceiptToken depositToken;
}

struct IdLookup {
  uint16 index;
  bool exists;
}
