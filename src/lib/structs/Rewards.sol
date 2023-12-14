// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";

struct RewardPool {
  IERC20 asset;
  uint256 amount;
}

struct ClaimedRewards {
  IERC20 token;
  uint128 amount;
}
