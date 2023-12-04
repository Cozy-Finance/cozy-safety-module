// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {ISafetyModule} from "./ISafetyModule.sol";

interface IStkToken is IERC20 {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(ISafetyModule safetyModule_, uint8 decimals_) external;
}
