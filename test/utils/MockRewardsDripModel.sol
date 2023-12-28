// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "../../src/interfaces/IRewardsDripModel.sol";

contract MockRewardsDripModel is IRewardsDripModel {
  uint256 public dripFactorConstant;

  constructor(uint256 dripFactorConstant_) {
    dripFactorConstant = dripFactorConstant_;
  }

  function dripFactor(uint256, /* lastDripTime_ */ uint256 /* currentTime_ */ )
    external
    view
    override
    returns (uint256)
  {
    return dripFactorConstant;
  }
}
