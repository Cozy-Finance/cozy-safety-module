// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface IRewardsDripModel {
  function dripFactor(IERC20 asset_) external returns (uint256 dripFactor_);
}
