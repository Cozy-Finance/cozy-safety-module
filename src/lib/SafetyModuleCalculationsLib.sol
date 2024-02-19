// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @notice Read-only safety module calculations.
 */
library SafetyModuleCalculationsLib {
  using FixedPointMathLib for uint256;

  uint256 internal constant POOL_AMOUNT_FLOOR = 1;

  /// @notice The `tokenAmount_` that the safety module would exchange for `assetAmount_` of receipt token provided.
  /// @dev See the ERC-4626 spec for more info.
  function convertToReceiptTokenAmount(uint256 assetAmount_, uint256 receiptTokenSupply_, uint256 poolAmount_)
    internal
    pure
    returns (uint256 receiptTokenAmount_)
  {
    receiptTokenAmount_ = receiptTokenSupply_ == 0
      ? assetAmount_
      : assetAmount_.mulDivDown(receiptTokenSupply_, _poolAmountWithFloor(poolAmount_));
  }

  /// @notice The `assetAmount_` that the safety module would exchange for `receiptTokenAmount_` of the receipt
  /// token. Note that we do not floor the pool amount here, as the pool amount never shows up in the denominator.
  /// @dev See the ERC-4626 spec for more info.
  function convertToAssetAmount(uint256 receiptTokenAmount_, uint256 receiptTokenSupply_, uint256 poolAmount_)
    internal
    pure
    returns (uint256 assetAmount_)
  {
    assetAmount_ = receiptTokenSupply_ == 0 ? 0 : receiptTokenAmount_.mulDivDown(poolAmount_, receiptTokenSupply_);
  }

  /// @notice The pool amount for the purposes of performing conversions. We set a floor once
  /// depositReceiptTokens have been initialized to avoid divide-by-zero errors that would occur when the supply
  /// of depositReceiptTokens > 0, but the `poolAmount` = 0.
  function _poolAmountWithFloor(uint256 poolAmount_) private pure returns (uint256) {
    return poolAmount_ > POOL_AMOUNT_FLOOR ? poolAmount_ : POOL_AMOUNT_FLOOR;
  }
}
