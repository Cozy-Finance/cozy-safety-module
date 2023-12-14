// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IRewardsDripModel} from "../../interfaces/IRewardsDripModel.sol";
import {IStkToken} from "../../interfaces/IStkToken.sol";
import {IDepositToken} from "../../interfaces/IDepositToken.sol";

struct TokenPool {
  // The total balance of tokens held by a SafetyModule, should be equivalent to
  // token.balanceOf(address(this)), discounting any tokens directly sent
  // to the SafetyModule via direct transfer.
  uint256 balance;
}

struct ReservePool {
  IERC20 token;
  IStkToken stkToken;
  IDepositToken depositToken;
  uint256 stakeAmount;
  uint256 depositAmount;
}

struct IdLookup {
  uint128 index;
  bool exists;
}
