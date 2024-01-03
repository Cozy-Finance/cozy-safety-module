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

  event ClaimedFees(IERC20 indexed reserveAsset_, uint256 feeAmount_, address indexed owner_);

  function dripFees() public override {
    uint256 deltaT_ = block.timestamp - dripTimes.lastFeesDripTime;
    if (deltaT_ == 0 || safetyModuleState != SafetyModuleState.ACTIVE) return;

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
    uint256 dripFactor_ =
      cozyManager.getFeeDripModel(ISafetyModule(address(this))).dripFactor(dripTimes.lastFeesDripTime, deltaT_);

    uint256 numReservePools_ = reservePools.length;
    for (uint16 i = 0; i < numReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools[i];
      uint256 stakeAmount_ = reservePool_.stakeAmount;
      uint256 depositAmount_ = reservePool_.depositAmount;

      uint256 drippedFromStakeAmount_ =
        _computeNextDripAmount(stakeAmount_ - reservePool_.pendingUnstakesAmount, dripFactor_);
      uint256 drippedFromDepositAmount_ =
        _computeNextDripAmount(depositAmount_ - reservePool_.pendingWithdrawalsAmount, dripFactor_);

      if (drippedFromStakeAmount_ > 0 || drippedFromDepositAmount_ > 0) {
        reservePool_.feeAmount += drippedFromStakeAmount_ + drippedFromDepositAmount_;
        reservePool_.stakeAmount -= drippedFromStakeAmount_;
        reservePool_.depositAmount -= drippedFromDepositAmount_;
      }
    }

    dripTimes.lastFeesDripTime = uint128(block.timestamp);
  }
}
