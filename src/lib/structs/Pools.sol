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
}

struct UndrippedRewardPool {
  IERC20 token;
  uint256 amount;
  IRewardsDripModel dripModel;
  uint128 lastDripTime;
  IReceiptToken depositToken;
}

struct DepositPool {
  IReceiptToken depositToken;
  uint256 depositAmount;
}

struct IdLookup {
  uint128 index;
  bool exists;
}
