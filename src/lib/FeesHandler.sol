// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {MathConstants} from "./MathConstants.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {UserRewardsData} from "./structs/Rewards.sol";
import {UndrippedRewardPool, IdLookup} from "./structs/Pools.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {IRewardsHandlerErrors} from "../interfaces/IRewardsHandlerErrors.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract FeesHandler is SafetyModuleCommon, IRewardsHandlerErrors {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;

  event ClaimedRewards(
    uint16 indexed reservePoolId,
    IERC20 indexed rewardAsset_,
    uint256 amount_,
    address indexed owner_,
    address receiver_
  );

  // TODO: Add a preview function which takes into account fees still to be dripped.

  function dripFees() public {
    uint256 deltaT_ = block.timestamp - lastDripTime;
    if (deltaT_ == 0 || safetyModuleState == SafetyModuleState.PAUSED) return;

    _dripFees(deltaT_);
  }

  function _dripFees(uint256 deltaT_) internal {
    uint256 lastDripTime_ = lastDripTime;
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
        reservePool_.feeAmount += totalDrippedFees_;
        (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_) =
          _getFeeAllocation(totalDrippedFees_, stakeAmount_, depositAmount_);
        reservePool_.stakeAmount -= drippedFromStakeAmount_;
        reservePool_.depositAmount -= drippedFromDepositAmount_;
      }
    }
  }

  function _getFeeAllocation(uint256 totalDrippedFees_, uint256 stakeAmount_, uint256 depositAmount_)
    internal
    pure
    returns (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_)
  {
    uint256 totalReserveAmount_ = stakeAmount_ + depositAmount_;
    if (totalReserveAmount_ == 0) return (0, 0);
    // Round down in favor of stakers and against depositors.
    drippedFromStakeAmount_ = totalDrippedFees_.mulWadDown(stakeAmount_).divWadDown(totalReserveAmount_);
    drippedFromDepositAmount_ = totalDrippedFees_ - drippedFromStakeAmount_;
  }
}
