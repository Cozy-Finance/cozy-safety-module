// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IRewardsDripModel} from "../../interfaces/IRewardsDripModel.sol";
import {IReceiptToken} from "../../interfaces/IReceiptToken.sol";

struct AssetPool {
  // The total balance of assets held by a SafetyModule, should be equivalent to
  // token.balanceOf(address(this)), discounting any assets directly sent
  // to the SafetyModule via direct transfer.
  uint256 amount;
}

struct ReservePool {
  IERC20 asset;
  IReceiptToken stkToken;
  IReceiptToken depositToken;
  uint256 stakeAmount;
  uint256 depositAmount;
  /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
  /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
  /// wrt totalSupply.
  uint16 rewardsPoolsWeight;
}

struct UndrippedRewardPool {
  IERC20 asset;
  uint256 amount;
  IRewardsDripModel dripModel;
  IReceiptToken depositToken;
}

struct IdLookup {
  uint16 index;
  bool exists;
}
