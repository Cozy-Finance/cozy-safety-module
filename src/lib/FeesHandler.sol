// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {Ownable} from "./Ownable.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {MathConstants} from "./MathConstants.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract FeesHandler is SafetyModuleCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;

  event ClaimedFees(IERC20 indexed reserveAsset_, uint256 feeAmount_, address indexed owner_);

  function dripFees() public override {
    if (safetyModuleState != SafetyModuleState.ACTIVE) return;
    IDripModel dripModel_ = cozyManager.getFeeDripModel(ISafetyModule(address(this)));

    uint256 numReserveAssets_ = reservePools.length;
    for (uint16 i = 0; i < numReserveAssets_; i++) {
      _dripFeesFromReservePool(reservePools[i], dripModel_);
    }
  }

  function dripFeesFromReservePool(uint16 reservePoolId_) external {
    if (safetyModuleState != SafetyModuleState.ACTIVE) return;
    IDripModel dripModel_ = cozyManager.getFeeDripModel(ISafetyModule(address(this)));

    _dripFeesFromReservePool(reservePools[reservePoolId_], dripModel_);
  }

  /// @notice Transfers accrued fees to the `owner_` address.
  /// @dev Validation is handled in the manager, which is the only account authorized to call this method.
  function claimFees(address owner_) external {
    // Cozy fee claims will often be batched, so we require it to be initiated from the manager to save gas by
    // removing calls and SLOADs to check the owner addresses each time.
    if (msg.sender != address(cozyManager)) revert Ownable.Unauthorized();
    IDripModel dripModel_ = cozyManager.getFeeDripModel(ISafetyModule(address(this)));

    uint256 numReservePools_ = reservePools.length;
    for (uint16 i = 0; i < numReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools[i];
      _dripFeesFromReservePool(reservePool_, dripModel_);

      uint256 feeAmount_ = reservePool_.feeAmount;
      if (feeAmount_ > 0) {
        IERC20 asset_ = reservePool_.asset;
        reservePool_.feeAmount = 0;
        assetPools[asset_].amount -= feeAmount_;
        asset_.safeTransfer(owner_, feeAmount_);

        emit ClaimedFees(asset_, feeAmount_, owner_);
      }
    }
  }

  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel dripModel_) internal override {
    uint256 dripFactor_ = dripModel_.dripFactor(reservePool_.lastFeesDripTime);
    if (dripFactor_ > MathConstants.WAD) revert InvalidDripFactor();

    uint256 drippedFromDepositAmount_ =
      _computeNextDripAmount(reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount, dripFactor_);

    if (drippedFromDepositAmount_ > 0) {
      reservePool_.feeAmount += drippedFromDepositAmount_;
      reservePool_.depositAmount -= drippedFromDepositAmount_;
    }

    reservePool_.lastFeesDripTime = uint128(block.timestamp);
  }

  function _computeNextDripAmount(uint256 totalBaseAmount_, uint256 dripFactor_)
    internal
    pure
    override
    returns (uint256)
  {
    return totalBaseAmount_.mulWadDown(dripFactor_);
  }

  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    override
    returns (uint256)
  {
    uint256 dripFactor_ = dripModel_.dripFactor(lastDripTime_);
    if (dripFactor_ > MathConstants.WAD) revert InvalidDripFactor();

    return _computeNextDripAmount(totalBaseAmount_, dripFactor_);
  }
}
