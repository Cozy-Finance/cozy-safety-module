// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract FeesHandler is SafetyModuleCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;

  /// @dev Emitted when fees are claimed.
  event ClaimedFees(IERC20 indexed reserveAsset_, uint256 feeAmount_, address indexed owner_);

  /// @inheritdoc SafetyModuleCommon
  function dripFees() public override {
    if (safetyModuleState != SafetyModuleState.ACTIVE) return;
    IDripModel dripModel_ = cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this)));

    uint256 numReserveAssets_ = reservePools.length;
    for (uint8 i = 0; i < numReserveAssets_; i++) {
      _dripFeesFromReservePool(reservePools[i], dripModel_);
    }
  }

  /// @notice Drips fees from a specific reserve pool.
  /// @param reservePoolId_ The ID of the reserve pool to drip fees from.
  function dripFeesFromReservePool(uint8 reservePoolId_) external {
    if (safetyModuleState != SafetyModuleState.ACTIVE) return;
    IDripModel dripModel_ = cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this)));

    _dripFeesFromReservePool(reservePools[reservePoolId_], dripModel_);
  }

  /// @notice Claims any accrued fees to the CozySafetyModuleManager owner.
  /// @dev Validation is handled in the CozySafetyModuleManager, which is the only account authorized to call this
  /// method.
  /// @param owner_ The address to transfer the fees to.
  /// @param dripModel_ The drip model to use for calculating fee drip.
  function claimFees(address owner_, IDripModel dripModel_) external {
    // Cozy fee claims will often be batched, so we require it to be initiated from the CozySafetyModuleManager to save
    // gas by removing calls and SLOADs to check the owner addresses each time.
    if (msg.sender != address(cozySafetyModuleManager)) revert Ownable.Unauthorized();

    uint256 numReservePools_ = reservePools.length;
    bool safetyModuleIsActive_ = safetyModuleState == SafetyModuleState.ACTIVE;
    for (uint8 i = 0; i < numReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools[i];
      _claimFees(reservePool_, dripModel_, safetyModuleIsActive_, owner_);
    }
  }

  /// @notice Claims any accrued fees for the specified reserve pools to the CozySafetyModuleManager owner.
  /// @param reservePoolIds_ The IDs of the reserve pools to claim fees from.
  function claimFees(uint8[] calldata reservePoolIds_) external {
    address receiver_ = cozySafetyModuleManager.owner();
    IDripModel dripModel_ = cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this)));

    bool safetyModuleIsActive_ = safetyModuleState == SafetyModuleState.ACTIVE;
    for (uint8 i = 0; i < reservePoolIds_.length; i++) {
      ReservePool storage reservePool_ = reservePools[reservePoolIds_[i]];
      _claimFees(reservePool_, dripModel_, safetyModuleIsActive_, receiver_);
    }
  }

  /// @notice Claims any accrued fees from the specified reserve pool to the specified receiver.
  /// @param reservePool_ The reserve pool to claim fees from.
  /// @param dripModel_ The drip model to use for calculating fee drip.
  /// @param safetyModuleIsActive Whether the safety module is active.
  /// @param receiver_ The address to transfer the fees to.
  function _claimFees(
    ReservePool storage reservePool_,
    IDripModel dripModel_,
    bool safetyModuleIsActive,
    address receiver_
  ) internal {
    if (safetyModuleIsActive) _dripFeesFromReservePool(reservePool_, dripModel_);

    uint256 feeAmount_ = reservePool_.feeAmount;
    if (feeAmount_ > 0) {
      IERC20 asset_ = reservePool_.asset;
      reservePool_.feeAmount = 0;
      assetPools[asset_].amount -= feeAmount_;
      asset_.safeTransfer(receiver_, feeAmount_);

      emit ClaimedFees(asset_, feeAmount_, receiver_);
    }
  }

  /// @notice Drips fees from the specified reserve pool.
  /// @param reservePool_ The reserve pool to drip fees from.
  /// @param dripModel_ The drip model to use for calculating the fees to drip.
  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel dripModel_) internal override {
    uint256 drippedFromDepositAmount_ = _getNextDripAmount(
      reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount, dripModel_, reservePool_.lastFeesDripTime
    );

    if (drippedFromDepositAmount_ > 0) {
      reservePool_.feeAmount += drippedFromDepositAmount_;
      reservePool_.depositAmount -= drippedFromDepositAmount_;
    }

    reservePool_.lastFeesDripTime = uint128(block.timestamp);
  }

  /// @inheritdoc SafetyModuleCommon
  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    override
    returns (uint256)
  {
    uint256 dripFactor_ = dripModel_.dripFactor(lastDripTime_, totalBaseAmount_);
    if (dripFactor_ > MathConstants.WAD) revert InvalidDripFactor();

    return totalBaseAmount_.mulWadDown(dripFactor_);
  }
}
