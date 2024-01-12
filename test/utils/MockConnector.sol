// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IConnector} from "../../src/interfaces/IConnector.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

/**
 * @notice A naive connector with a fixed exchange rate for base to wrapped assets.
 * @dev This is used for tests. We should do integration tests with the actual connectors (e.g. AaveV3Connector).
 */
contract MockConnector is IConnector {
  using FixedPointMathLib for uint256;

  MockERC20 public asset;
  MockERC20 public wrappedAsset;
  uint256 assetToWrappedAssetRate;

  constructor(MockERC20 asset_, MockERC20 wrappedAsset_) {
    asset = asset_;
    wrappedAsset = wrappedAsset_;
    assetToWrappedAssetRate = 2;
  }

  function convertToBaseAssetsNeeded(uint256 assets_) external view returns (uint256) {
    return assets_ / assetToWrappedAssetRate;
  }

  function convertToWrappedAssets(uint256 assets_) external view returns (uint256) {
    return assets_ * assetToWrappedAssetRate;
  }

  function wrapBaseAsset(address recipient_, uint256 amount_) external returns (uint256 wrappedAssetAmount_) {
    wrappedAssetAmount_ = amount_ * assetToWrappedAssetRate;
    wrappedAsset.mint(recipient_, wrappedAssetAmount_);
  }

  function unwrapWrappedAsset(address recipient_, uint256 amount_) external returns (uint256 baseAssetAmount_) {
    baseAssetAmount_ = amount_ / assetToWrappedAssetRate;
    wrappedAsset.burn(address(this), amount_);
    asset.transfer(recipient_, baseAssetAmount_);
  }

  function baseAsset() external view returns (IERC20) {
    return IERC20(address(asset));
  }

  function balanceOf(address account_) external view returns (uint256) {
    return wrappedAsset.balanceOf(account_);
  }
}
