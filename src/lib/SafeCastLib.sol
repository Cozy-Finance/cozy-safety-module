// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

/**
 * @dev Wrappers over Solidity's casting operators that revert if the input overflows the new type when downcasted.
 */
library SafeCastLib {
  /// @dev Thrown when a downcast fails.
  error SafeCastFailed();

  /// @dev Downcast `x` to a `uint216`, reverting if `x > type(uint216).max`.
  function safeCastTo216(uint256 x) internal pure returns (uint216 y) {
    if (x > type(uint216).max) revert SafeCastFailed();
    y = uint216(x);
  }

  /// @dev Downcast `x` to a `uint176`, reverting if `x > type(uint176).max`.
  function safeCastTo176(uint256 x) internal pure returns (uint176 y) {
    if (x > type(uint176).max) revert SafeCastFailed();
    y = uint176(x);
  }

  /// @dev Downcast `x` to a `uint128`, reverting if `x > type(uint128).max`.
  function safeCastTo128(uint256 x) internal pure returns (uint128 y) {
    if (x > type(uint128).max) revert SafeCastFailed();
    y = uint128(x);
  }

  /// @dev Downcast `x` to a `uint96`, reverting if `x > type(uint96).max`.
  function safeCastTo96(uint256 x) internal pure returns (uint96 y) {
    if (x > type(uint96).max) revert SafeCastFailed();
    y = uint96(x);
  }

  /// @dev Downcast `x` to a `uint64`, reverting if `x > type(uint64).max`.
  function safeCastTo64(uint256 x) internal pure returns (uint64 y) {
    if (x > type(uint64).max) revert SafeCastFailed();
    y = uint64(x);
  }

  // @dev Downcast `x` to a `uint40`, reverting if `x > type(uint40).max`.
  function safeCastTo40(uint256 x) internal pure returns (uint40 y) {
    if (x > type(uint40).max) revert SafeCastFailed();
    y = uint40(x);
  }

  // @dev Downcast `x` to a `uint48`, reverting if `x > type(uint48).max`.
  function safeCastTo48(uint256 x) internal pure returns (uint48 y) {
    if (x > type(uint48).max) revert SafeCastFailed();
    y = uint48(x);
  }

  /// @dev Downcast `x` to a `uint32`, reverting if `x > type(uint32).max`.
  function safeCastTo32(uint256 x) internal pure returns (uint32 y) {
    if (x > type(uint32).max) revert SafeCastFailed();
    y = uint32(x);
  }

  /// @dev Downcast `x` to a `uint16`, reverting if `x > type(uint16).max`.
  function safeCastTo16(uint256 x) internal pure returns (uint16 y) {
    if (x > type(uint16).max) revert SafeCastFailed();
    y = uint16(x);
  }
}
