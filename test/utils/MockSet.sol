// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";

contract MockSafetyModule {
  IERC20 public asset;

  constructor(IERC20 asset_) {
    asset = asset_;
  }
}
