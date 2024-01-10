// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

interface IConnector {
  /// @notice Calculates the minimum amount of base assets needed to get back at least `assets_` amount of the wrapped
  /// tokens.
  function convertToBaseAssetsNeeded(uint256 assets_) external view returns (uint256);

  /// @notice Calculates the amount of wrapped tokens needed for `assets_` amount of the base asset.
  function convertToWrappedAssets(uint256 assets_) external view returns (uint256);

  /// @notice Wraps the base asset and mints wrapped tokens to the `receiver_` address.
  function wrapBaseAsset(address recipient_, uint256 amount_) external returns (uint256);

  /// @notice Unwraps the wrapped tokens and sends base assets to the `receiver_` address.
  function unwrapWrappedAsset(address recipient_, uint256 amount_) external returns (uint256);

  /// @notice Returns the base asset address.
  function baseAsset() external view returns (IERC20);

  /// @notice Returns the amount of wrapped tokens owned by `account_`.
  function balanceOf(address account_) external view returns (uint256);
}
