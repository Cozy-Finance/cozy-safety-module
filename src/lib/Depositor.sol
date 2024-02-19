// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";

abstract contract Depositor is SafetyModuleCommon, IDepositorErrors {
  using SafeERC20 for IERC20;

  /// @dev Emitted when a user deposits.
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed depositReceiptToken_,
    uint256 assetAmount_,
    uint256 depositReceiptTokenAmount_
  );

  /// @dev Expects `from_` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_].asset` so it can `transferFrom`
  function depositReserveAssets(uint8 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositReceiptTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];

    IERC20 underlyingToken_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[underlyingToken_];

    // Pull in deposited assets. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    underlyingToken_.safeTransferFrom(from_, address(this), reserveAssetAmount_);

    depositReceiptTokenAmount_ =
      _executeReserveDeposit(underlyingToken_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint8 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 underlyingToken_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[underlyingToken_];

    depositReceiptTokenAmount_ =
      _executeReserveDeposit(underlyingToken_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  function _executeReserveDeposit(
    IERC20 underlyingToken_,
    uint256 reserveAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 depositReceiptTokenAmount_) {
    _assertValidDepositState();
    _assertValidDepositBalance(underlyingToken_, assetPool_.amount, reserveAssetAmount_);

    _dripFeesFromReservePool(reservePool_, cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))));

    IReceiptToken depositReceiptToken_ = reservePool_.depositReceiptToken;
    // Fees were dripped already in this function, so we can use the SafetyModuleCalculationsLib directly.
    depositReceiptTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_,
      depositReceiptToken_.totalSupply(),
      reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount
    );
    if (depositReceiptTokenAmount_ == 0) revert RoundsToZero();

    // Increment reserve pool accounting only after calculating `depositReceiptTokenAmount_` to mint.
    reservePool_.depositAmount += reserveAssetAmount_;
    assetPool_.amount += reserveAssetAmount_;

    depositReceiptToken_.mint(receiver_, depositReceiptTokenAmount_);
    emit Deposited(msg.sender, receiver_, depositReceiptToken_, reserveAssetAmount_, depositReceiptTokenAmount_);
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
