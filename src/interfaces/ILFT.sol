// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {MintData} from "../lib/structs/MintData.sol";

/**
 * @dev Interface for LFT tokens.
 */
interface ILFT is IERC20 {
  /// @notice Returns the array of metadata for all tokens minted to `user`.
  function getMints(address user_) external view returns (MintData[] memory);

  /// @notice Returns the quantity of matured tokens held by the given `user_`.
  /// @dev A user's `balanceOfMatured` is computed by starting with `balanceOf[user_]` then subtracting the sum of
  /// all `amounts` from the  user's `mints` array that are not yet matured. How to determine when a given mint
  /// is matured is left to the implementer. It can be simple such as maturing when `block.timestamp >= time + delay`,
  /// or something more complex.
  function balanceOfMatured(address user_) external view returns (uint256);

  /// @notice Moves `amount_` tokens from the caller's account to `to_`. Tokens must be matured to transfer them.
  function transfer(address to_, uint256 amount_) external returns (bool);

  /// @notice Moves `amount_` tokens from `from_` to `to_`. Tokens must be matured to transfer them.
  function transferFrom(address from_, address to_, uint256 amount_) external returns (bool);
}
