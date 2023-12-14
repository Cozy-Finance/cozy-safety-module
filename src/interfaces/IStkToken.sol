// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {ISafetyModule} from "./ISafetyModule.sol";

interface IStkToken is IERC20 {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(ISafetyModule safetyModule_, uint8 decimals_) external;

  /// @notice Mints `amount_` of tokens to `to_`.
  function mint(address to_, uint256 amount_) external;

  /// @notice Burns `amount_` of tokens from `from`_.
  function burn(address caller_, address from_, uint256 amount_) external;
}
