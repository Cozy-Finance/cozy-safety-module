// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/**
 * @dev Helper methods for common math operations.
 */
library CozyMath {
  /// @dev Performs `x * y` without overflow checks. Only use this when you are sure `x * y` will not overflow.
  function unsafemul(uint256 x, uint256 y) internal pure returns (uint256 z) {
    assembly {
      z := mul(x, y)
    }
  }

  /// @dev Performs `x / y` without divide by zero checks. Only use this when you are sure `y` is not zero.
  function unsafediv(uint256 x, uint256 y) internal pure returns (uint256 z) {
    // Only use this when you are sure y is not zero.
    assembly {
      z := div(x, y)
    }
  }

  /// @dev Returns `x - y` if the result is positive, or zero if `x - y` would overflow and result in a negative value.
  function differenceOrZero(uint256 x, uint256 y) internal pure returns (uint256 z) {
    unchecked {
      z = x >= y ? x - y : 0;
    }
  }

  function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = x > y ? y : x;
  }
}
