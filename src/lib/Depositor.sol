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

  /// @dev Emitted when a user deposits reserve assets.
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    uint8 indexed reservePoolId_,
    IReceiptToken depositReceiptToken_,
    uint256 assetAmount_,
    uint256 depositReceiptTokenAmount_
  );

  /// @notice Deposits reserve assets into the SafetyModule and mints deposit receipt tokens.
  /// @dev Expects `from_` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_].asset` so it can `transferFrom` the assets to this SafetyModule.
  /// @param reservePoolId_ The ID of the reserve pool to deposit assets into.
  /// @param reserveAssetAmount_ The amount of reserve assets to deposit.
  /// @param receiver_ The address to receive the deposit receipt tokens.
  /// @param from_ The address that is depositing the reserve assets.
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
      _executeReserveDeposit(reservePoolId_, underlyingToken_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @notice Deposits reserve assets into the SafetyModule and mints deposit receipt tokens.
  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  /// @param reservePoolId_ The ID of the reserve pool to deposit assets into.
  /// @param reserveAssetAmount_ The amount of reserve assets to deposit.
  /// @param receiver_ The address to receive the deposit receipt tokens.
  function depositReserveAssetsWithoutTransfer(uint8 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 underlyingToken_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[underlyingToken_];

    depositReceiptTokenAmount_ =
      _executeReserveDeposit(reservePoolId_, underlyingToken_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @notice Deposits reserve assets into the SafetyModule and mints deposit receipt tokens.
  /// @param reservePoolId_ The ID of the reserve pool to deposit assets into.
  /// @param underlyingToken_ The address of the underlying token to deposit.
  /// @param reserveAssetAmount_ The amount of reserve assets to deposit.
  /// @param receiver_ The address to receive the deposit receipt tokens.
  /// @param assetPool_ The asset pool for the underlying asset of the reserve pool that is being deposited into.
  /// @param reservePool_ The reserve pool to deposit assets into.
  function _executeReserveDeposit(
    uint8 reservePoolId_,
    IERC20 underlyingToken_,
    uint256 reserveAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 depositReceiptTokenAmount_) {
    SafetyModuleState safetyModuleState_ = safetyModuleState;
    if (safetyModuleState_ == SafetyModuleState.PAUSED) revert InvalidState();

    // Ensure the deposit amount is valid w.r.t. the balance of the SafetyModule.
    if (underlyingToken_.balanceOf(address(this)) - assetPool_.amount < reserveAssetAmount_) revert InvalidDeposit();

    IReceiptToken depositReceiptToken_ = reservePool_.depositReceiptToken;
    if (safetyModuleState_ == SafetyModuleState.ACTIVE) {
      _dripFeesFromReservePool(reservePool_, cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))));
      depositReceiptTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
        reserveAssetAmount_,
        depositReceiptToken_.totalSupply(),
        // Fees were dripped in this block, so we don't need to subtract next drip amount.
        reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount
      );
    } else {
      // If the SafetyModule is TRIGGERED, we calculate the exchange rate with consideration for the next drip amount,
      // but we don't actually drip the fees. Fees can only be dripped when the SafetyModule is active.
      uint256 totalPoolAmount_ = reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount;
      depositReceiptTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
        reserveAssetAmount_,
        depositReceiptToken_.totalSupply(),
        totalPoolAmount_
          - _getNextDripAmount(
            totalPoolAmount_,
            cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))),
            reservePool_.lastFeesDripTime
          )
      );
    }
    if (depositReceiptTokenAmount_ == 0) revert RoundsToZero();

    // Increment reserve pool accounting only after calculating `depositReceiptTokenAmount_` to mint.
    reservePool_.depositAmount += reserveAssetAmount_;
    assetPool_.amount += reserveAssetAmount_;

    depositReceiptToken_.mint(receiver_, depositReceiptTokenAmount_);
    emit Deposited(
      msg.sender, receiver_, reservePoolId_, depositReceiptToken_, reserveAssetAmount_, depositReceiptTokenAmount_
    );
  }
}
