// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface IRewardsDripModel {
  function dripFactor(uint256 lastDripTime_, uint256 currentTime_) external view returns (uint256 dripFactor_);
}
