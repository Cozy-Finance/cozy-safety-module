// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IRewardsDripModel} from "../../interfaces/IRewardsDripModel.sol";
import {IStkToken} from "../../interfaces/IStkToken.sol";
import {IDepositToken} from "../../interfaces/IDepositToken.sol";

struct AssetPool {
  // The total balance of assets held by a SafetyModule, should be equivalent to
  // token.balanceOf(address(this)), discounting any assets directly sent
  // to the SafetyModule via direct transfer.
  uint256 amount;
}

struct ReservePool {
  IERC20 asset;
  IStkToken stkToken;
  IDepositToken depositToken;
  uint256 stakeAmount;
  uint256 depositAmount;
}

struct IdLookup {
  uint128 index;
  bool exists;
}
