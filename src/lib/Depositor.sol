// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {ReservePool, AssetPool, UndrippedRewardPool} from "./structs/Pools.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract Depositor is SafetyModuleCommon, IDepositorErrors {
  using SafeERC20 for IERC20;

  /// @dev Emitted when a user deposits.
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed depositToken_,
    uint256 assetAmount_,
    uint256 depositTokenAmount_
  );

  /// @dev Expects `from_` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_].asset` so it can `transferFrom`
  function depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];

    IERC20 underlyingToken_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[underlyingToken_];

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    underlyingToken_.safeTransferFrom(from_, address(this), reserveAssetAmount_);

    depositTokenAmount_ =
      _executeReserveDeposit(underlyingToken_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 underlyingToken_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[underlyingToken_];

    depositTokenAmount_ =
      _executeReserveDeposit(underlyingToken_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositTokenAmount_)
  {
    UndrippedRewardPool storage rewardsPool_ = undrippedRewardPools[rewardPoolId_];

    IERC20 underlyingToken_ = rewardsPool_.asset;
    AssetPool storage assetPool_ = assetPools[underlyingToken_];

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    underlyingToken_.safeTransferFrom(from_, address(this), rewardAssetAmount_);

    depositTokenAmount_ =
      _executeRewardDeposit(underlyingToken_, rewardAssetAmount_, receiver_, assetPool_, rewardsPool_);
  }

  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_)
  {
    UndrippedRewardPool storage rewardsPool_ = undrippedRewardPools[rewardPoolId_];
    IERC20 underlyingToken_ = rewardsPool_.asset;
    AssetPool storage assetPool_ = assetPools[underlyingToken_];

    depositTokenAmount_ =
      _executeRewardDeposit(underlyingToken_, rewardAssetAmount_, receiver_, assetPool_, rewardsPool_);
  }

  function _executeReserveDeposit(
    IERC20 underlyingToken_,
    uint256 reserveAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 depositTokenAmount_) {
    _assertValidDepositState();
    _assertValidDepositBalance(underlyingToken_, assetPool_.amount, reserveAssetAmount_);

    IReceiptToken depositToken_ = reservePool_.depositToken;

    depositTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, depositToken_.totalSupply(), reservePool_.depositAmount
    );
    // Increment reserve pool accounting only after calculating `depositTokenAmount_` to mint.
    reservePool_.depositAmount += reserveAssetAmount_;
    assetPool_.amount += reserveAssetAmount_;

    depositToken_.mint(receiver_, depositTokenAmount_);
    emit Deposited(msg.sender, receiver_, depositToken_, reserveAssetAmount_, depositTokenAmount_);
  }

  function _executeRewardDeposit(
    IERC20 token_,
    uint256 rewardAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    UndrippedRewardPool storage rewardPool_
  ) internal returns (uint256 depositTokenAmount_) {
    _assertValidDepositState();
    _assertValidDepositBalance(token_, assetPool_.amount, rewardAssetAmount_);

    IReceiptToken depositToken_ = rewardPool_.depositToken;

    depositTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      rewardAssetAmount_, depositToken_.totalSupply(), rewardPool_.amount
    );
    // Increment reward pool accounting only after calculating `depositTokenAmount_` to mint.
    rewardPool_.amount += rewardAssetAmount_;
    assetPool_.amount += rewardAssetAmount_;

    depositToken_.mint(receiver_, depositTokenAmount_);
    emit Deposited(msg.sender, receiver_, depositToken_, rewardAssetAmount_, depositTokenAmount_);
  }

  function _assertValidDepositBalance(IERC20 token_, uint256 assetPoolBalance_, uint256 depositAmount_)
    internal
    view
    override
  {
    if (token_.balanceOf(address(this)) - assetPoolBalance_ < depositAmount_) revert InvalidDeposit();
  }

  function _assertValidDepositState() internal view {
    if (safetyModuleState == SafetyModuleState.PAUSED) revert InvalidState();
  }
}
