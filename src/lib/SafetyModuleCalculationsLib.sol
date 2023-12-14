// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @notice Read-only safety module calculations.
 */
library SafetyModuleCalculationsLib {
  using FixedPointMathLib for uint256;

  uint256 internal constant RESERVE_POOL_AMOUNT_FLOOR = 1;

  /// @notice The `tokenAmount_` that the safety module would exchange for `assetAmount_` of receipt token provided.
  /// @dev See the ERC-4626 spec for more info.
  function convertToReceiptTokenAmount(uint256 assetAmount_, uint256 tokenSupply_, uint256 reservePoolAmount_)
    internal
    pure
    returns (uint256 stkTokenAmount_)
  {
    stkTokenAmount_ = tokenSupply_ == 0
      ? assetAmount_
      : assetAmount_.mulDivDown(tokenSupply_, _reservePoolAmountWithFloor(reservePoolAmount_));
  }

  /// @notice The `reserveAssetAmount_` that the safety module would exchange for `receiptTokenAmount_` of the receipt token.
  /// @dev See the ERC-4626 spec for more info.
  function convertToReserveAssetAmount(uint256 receiptTokenAmount_, uint256 receiptTokenSupply_, uint256 reservePoolAmount_)
    internal
    pure
    returns (uint256 reserveAssetAmount_)
  {
    reserveAssetAmount_ = receiptTokenSupply_ == 0
      ? reservePoolAmount_
      : receiptTokenAmount_.mulDivDown(_reservePoolAmountWithFloor(reservePoolAmount_), receiptTokenSupply_);
  }

  /// @notice The reserve pool amount for the purposes of performing conversions. We set a floor once
  /// stkTokens have been initialized to avoid divide-by-zero errors that would occur when the supply
  /// of stkTokens > 0, but the `reservePoolAmount` = 0.
  function _reservePoolAmountWithFloor(uint256 reservePoolAmount_) private pure returns (uint256) {
    return reservePoolAmount_ > RESERVE_POOL_AMOUNT_FLOOR ? reservePoolAmount_ : RESERVE_POOL_AMOUNT_FLOOR;
  }
}
