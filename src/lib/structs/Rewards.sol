// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IRewardsDripModel} from "../../interfaces/IRewardsDripModel.sol";

struct RewardPool {
  IERC20 token;
  uint256 amount;
}

struct UndrippedRewardPool {
  IERC20 token;
  uint128 amount;
  IRewardsDripModel dripModel;
  uint128 lastDripTime;
}

struct ClaimedRewards {
  IERC20 token;
  uint128 amount;
}
