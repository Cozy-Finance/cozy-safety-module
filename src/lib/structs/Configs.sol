// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IRewardsDripModel} from "../../interfaces/IRewardsDripModel.sol";

struct RewardPoolConfig {
  IERC20 asset;
  IRewardsDripModel dripModel;
  uint16 weight;
}
