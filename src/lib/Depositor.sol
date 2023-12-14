// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {DepositPool, ReservePool, AssetPool, UndrippedRewardPool} from "./structs/Pools.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract Depositor is SafetyModuleCommon, IDepositorErrors {
  using SafeERC20 for IERC20;

  /// @dev Emitted when a user stakes.
  event Deposited(address indexed caller_, address indexed receiver_, uint256 amount_, uint256 depositTokenAmount_);

  /// @dev Expects `from_` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_]` so it can
  /// `transferFrom`
  function depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];

    IERC20 token_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[token_];

    // Pull in stake tokens. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    token_.safeTransferFrom(from_, address(this), reserveAssetAmount_);
    _assertValidDeposit(token_, assetPool_.amount, reserveAssetAmount_);

    depositTokenAmount_ = _executeReserveDeposit(reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 token_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[token_];

    _assertValidDeposit(token_, assetPool_.amount, reserveAssetAmount_);

    depositTokenAmount_ = _executeReserveDeposit(reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  function depositRewardAssets(
    uint16 claimableRewardPoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    address from_
  ) external returns (uint256 depositTokenAmount_) {
    UndrippedRewardPool storage rewardsPool_ = undrippedRewardPools[claimableRewardPoolId_];

    IERC20 token_ = rewardsPool_.asset;
    AssetPool storage assetPool_ = assetPools[token_];

    // Pull in stake tokens. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    token_.safeTransferFrom(from_, address(this), reserveAssetAmount_);
    _assertValidDeposit(token_, assetPool_.amount, reserveAssetAmount_);

    depositTokenAmount_ = _executeRewardDeposit(reserveAssetAmount_, receiver_, assetPool_, rewardsPool_);
  }

  function depositRewardAssetsWithoutTransfer(
    uint16 claimableRewardPoolId_,
    uint256 reserveAssetAmount_,
    address receiver_
  ) external returns (uint256 depositTokenAmount_) {
    UndrippedRewardPool storage rewardsPool_ = undrippedRewardPools[claimableRewardPoolId_];
    IERC20 token_ = rewardsPool_.asset;
    AssetPool storage assetPool_ = assetPools[token_];

    _assertValidDeposit(token_, assetPool_.amount, reserveAssetAmount_);

    depositTokenAmount_ = _executeRewardDeposit(reserveAssetAmount_, receiver_, assetPool_, rewardsPool_);
  }

  function _executeReserveDeposit(
    uint256 reserveAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 depositTokenAmount_) {
    if (safetyModuleState != SafetyModuleState.ACTIVE) revert InvalidState();

    IReceiptToken depositToken_ = reservePool_.depositToken;

    depositTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, depositToken_.totalSupply(), reservePool_.depositAmount
    );
    // Increment reserve pool accounting only after calculating `depositTokenAmount_` to mint.
    reservePool_.depositAmount += reserveAssetAmount_;
    assetPool_.amount += reserveAssetAmount_;

    depositToken_.mint(receiver_, depositTokenAmount_);
    emit Deposited(msg.sender, receiver_, reserveAssetAmount_, depositTokenAmount_);
  }

  function _executeRewardDeposit(
    uint256 reserveAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    UndrippedRewardPool storage rewardPool_
  ) internal returns (uint256 depositTokenAmount_) {
    if (safetyModuleState != SafetyModuleState.ACTIVE) revert InvalidState();

    IReceiptToken depositToken_ = rewardPool_.depositToken;

    depositTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, depositToken_.totalSupply(), rewardPool_.amount
    );
    // Increment reserve pool accounting only after calculating `depositTokenAmount_` to mint.
    rewardPool_.amount += reserveAssetAmount_;
    assetPool_.amount += reserveAssetAmount_;

    depositToken_.mint(receiver_, depositTokenAmount_);
    emit Deposited(msg.sender, receiver_, reserveAssetAmount_, depositTokenAmount_);
  }

  function _assertValidDeposit(IERC20 token_, uint256 assetPoolBalance_, uint256 depositAmount_) internal view override {
    if (token_.balanceOf(address(this)) - assetPoolBalance_ < depositAmount_) revert InvalidDeposit();
  }
}
