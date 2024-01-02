// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {Ownable} from "./Ownable.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {UndrippedRewardPool, IdLookup} from "./structs/Pools.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract FeesHandler is SafetyModuleCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;

  event ClaimedFees(IERC20 indexed reserveAsset_, uint256 feeAmount_, address indexed owner_);

  function dripFees() public override {
    uint256 deltaT_ = block.timestamp - lastFeesDripTime;
    if (deltaT_ == 0 || safetyModuleState == SafetyModuleState.PAUSED) return;

    _dripFees(deltaT_);
  }

  /// @notice Transfers accrued fees to the `owner_` address.
  /// @dev Validation is handled in the manager, which is the only account authorized to call this method.
  function claimFees(address owner_) external {
    // Cozy fee claims will often be batched, so we require it to be initiated from the manager to save gas by
    // removing calls and SLOADs to check the owner addresses each time.
    if (msg.sender != address(cozyManager)) revert Ownable.Unauthorized();

    dripFees();

    uint256 numReservePools_ = reservePools.length;
    for (uint16 i = 0; i < numReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools[i];
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

  function _dripFees(uint256 deltaT_) internal {
    uint256 lastDripTime_ = lastFeesDripTime;
    uint256 numReservePools_ = reservePools.length;

    IDripModel feeDripModel_ = cozyManager.getFeeDripModel(ISafetyModule(address(this)));

    for (uint16 i = 0; i < numReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools[i];
      uint256 stakeAmount_ = reservePool_.stakeAmount;
      uint256 depositAmount_ = reservePool_.depositAmount;

      uint256 totalDrippedFees_ = _getNextDripAmount(
        stakeAmount_ + depositAmount_ - reservePool_.pendingRedemptionsAmount, feeDripModel_, lastDripTime_, deltaT_
      );

      if (totalDrippedFees_ > 0) {
        (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_) =
          _getFeeAllocation(totalDrippedFees_, stakeAmount_, depositAmount_);
        reservePool_.feeAmount += drippedFromStakeAmount_ + drippedFromDepositAmount_;
        reservePool_.stakeAmount -= drippedFromStakeAmount_;
        reservePool_.depositAmount -= drippedFromDepositAmount_;
      }
    }

    lastFeesDripTime = block.timestamp;
  }

  function _getFeeAllocation(uint256 totalDrippedFees_, uint256 stakeAmount_, uint256 depositAmount_)
    internal
    pure
    returns (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_)
  {
    uint256 totalReserveAmount_ = stakeAmount_ + depositAmount_;
    if (totalReserveAmount_ == 0) return (0, 0);
    // Round down in favor of stakers and against depositors.
    drippedFromStakeAmount_ = totalDrippedFees_.mulWadDown(stakeAmount_.divWadDown(totalReserveAmount_));
    drippedFromDepositAmount_ = totalDrippedFees_ - drippedFromStakeAmount_;
    if (drippedFromDepositAmount_ > depositAmount_) drippedFromDepositAmount_ = depositAmount_;
  }
}
