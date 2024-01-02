// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IDripModel {
  function dripFactor(uint256 lastDripTime_, uint256 timeSinceLastDrip_) external view returns (uint256 dripFactor_);
}
