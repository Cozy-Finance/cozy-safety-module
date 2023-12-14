// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @notice Read-only safety module calculations.
 */
library SafetyModuleCalculationsLib {
  using FixedPointMathLib for uint256;

  uint256 internal constant RESERVE_POOL_AMOUNT_FLOOR = 1;

  /// @notice The `stkTokenAmount_` that the safety module would exchange for `amount_` of reserve token provided.
  /// @dev See the ERC-4626 spec for more info.
  function convertToStkTokenAmount(uint256 amount_, uint256 stkTokenSupply_, uint256 reservePoolAmount_)
    internal
    pure
    returns (uint256 stkTokenAmount_)
  {
    stkTokenAmount_ = stkTokenSupply_ == 0
      ? amount_
      : amount_.mulDivDown(stkTokenSupply_, _reservePoolAmountWithFloor(reservePoolAmount_));
  }

  /// @notice The `reserveTokenAmount_` that the safety module would exchange for `stkTokenAmount_` of the stkToken.
  /// @dev See the ERC-4626 spec for more info.
  function convertToReserveTokenAmount(uint256 stkTokenAmount_, uint256 stkTokenSupply_, uint256 reservePoolAmount_)
    internal
    pure
    returns (uint256 reserveTokenAmount_)
  {
    reserveTokenAmount_ = stkTokenSupply_ == 0
      ? reservePoolAmount_
      : stkTokenAmount_.mulDivDown(_reservePoolAmountWithFloor(reservePoolAmount_), stkTokenSupply_);
  }

  /// @notice The reserve pool amount for the purposes of performing conversions. We set a floor once
  /// stkTokens have been initialized to avoid divide-by-zero errors that would occur when the supply
  /// of stkTokens > 0, but the `reservePoolAmount` = 0.
  function _reservePoolAmountWithFloor(uint256 reservePoolAmount_) private pure returns (uint256) {
    return reservePoolAmount_ > RESERVE_POOL_AMOUNT_FLOOR ? reservePoolAmount_ : RESERVE_POOL_AMOUNT_FLOOR;
  }
}
