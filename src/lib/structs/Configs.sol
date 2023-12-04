// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IRewardsDripModel} from "../../interfaces/IRewardsDripModel.sol";

struct RewardPoolConfig {
  IERC20 token;
  IRewardsDripModel dripModel;
  uint16 weight;
}
