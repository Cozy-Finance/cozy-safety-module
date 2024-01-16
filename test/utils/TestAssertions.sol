// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {UndrippedRewardPool, ReservePool} from "../../src/lib/structs/Pools.sol";
import {
  UserRewardsData,
  PreviewClaimableRewardsData,
  PreviewClaimableRewards,
  ClaimableRewardsData
} from "../../src/lib/structs/Rewards.sol";
import {SafetyModuleState, TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {Test} from "forge-std/Test.sol";

abstract contract TestAssertions is Test {
  function assertEq(uint256[][] memory actual_, uint256[][] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ReservePool[] memory actual_, ReservePool[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ReservePool memory actual_, ReservePool memory expected_) internal {
    assertEq(address(actual_.asset), address(expected_.asset), "ReservePool.asset");
    assertEq(address(actual_.stkToken), address(expected_.stkToken), "ReservePool.stkToken");
    assertEq(address(actual_.depositToken), address(expected_.depositToken), "ReservePool.depositToken");
    assertEq(actual_.stakeAmount, expected_.stakeAmount, "ReservePool.stakeAmount");
    assertEq(actual_.depositAmount, expected_.depositAmount, "ReservePool.depositAmount");
    assertEq(actual_.pendingUnstakesAmount, expected_.pendingUnstakesAmount, "ReservePool.pendingUnstakesAmount");
    assertEq(
      actual_.pendingWithdrawalsAmount, expected_.pendingWithdrawalsAmount, "ReservePool.pendingWithdrawalsAmount"
    );
    assertEq(actual_.feeAmount, expected_.feeAmount, "ReservePool.feeAmount");
    assertEq(actual_.rewardsPoolsWeight, expected_.rewardsPoolsWeight, "ReservePool.rewardsPoolsWeight");
    assertEq(actual_.maxSlashPercentage, expected_.maxSlashPercentage, "ReservePool.maxSlashPercentage");
  }

  function assertEq(UndrippedRewardPool[] memory actual_, UndrippedRewardPool[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(UndrippedRewardPool memory actual_, UndrippedRewardPool memory expected_) internal {
    assertEq(address(actual_.asset), address(expected_.asset), "UndrippedRewardPool.asset");
    assertEq(address(actual_.dripModel), address(expected_.dripModel), "UndrippedRewardPool.dripModel");
    assertEq(address(actual_.depositToken), address(expected_.depositToken), "UndrippedRewardPool.depositToken");
    assertEq(actual_.amount, expected_.amount, "UndrippedRewardPool.amount");
  }

  function assertEq(UserRewardsData[] memory actual_, UserRewardsData[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(UserRewardsData memory actual_, UserRewardsData memory expected_) internal {
    assertEq(actual_.accruedRewards, expected_.accruedRewards, "UndrippedRewardPool.accruedRewards");
    assertEq(actual_.indexSnapshot, expected_.indexSnapshot, "UndrippedRewardPool.indexSnapshot");
  }

  function assertEq(SafetyModuleState actual_, SafetyModuleState expected_) internal {
    assertEq(uint256(actual_), uint256(expected_), "SafetyModuleState");
  }

  function assertEq(TriggerState actual_, TriggerState expected_) internal {
    assertEq(uint256(actual_), uint256(expected_), "TriggerState");
  }

  function assertEq(ClaimableRewardsData[][] memory actual_, ClaimableRewardsData[][] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ClaimableRewardsData[] memory actual_, ClaimableRewardsData[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(ClaimableRewardsData memory actual_, ClaimableRewardsData memory expected_) internal {
    assertEq(
      actual_.cumulativeDrippedRewards,
      expected_.cumulativeDrippedRewards,
      "ClaimableRewardsData.cumulativeDrippedRewards"
    );
    assertEq(actual_.indexSnapshot, expected_.indexSnapshot, "ClaimableRewardsData.indexSnapshot");
  }

  function assertEq(PreviewClaimableRewards[] memory actual_, PreviewClaimableRewards[] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(PreviewClaimableRewards memory actual_, PreviewClaimableRewards memory expected_) internal {
    assertEq(actual_.reservePoolId, expected_.reservePoolId, "PreviewClaimableRewards.reservePoolId");
    for (uint256 i = 0; i < actual_.claimableRewardsData.length; i++) {
      assertEq(actual_.claimableRewardsData[i], expected_.claimableRewardsData[i]);
    }
  }

  function assertEq(PreviewClaimableRewardsData[] memory actual_, PreviewClaimableRewardsData[] memory expected_)
    internal
  {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
  }

  function assertEq(PreviewClaimableRewardsData memory actual_, PreviewClaimableRewardsData memory expected_) internal {
    assertEq(address(actual_.asset), address(expected_.asset), "PreviewClaimableRewardsData.asset");
    assertEq(actual_.amount, expected_.amount, "PreviewClaimableRewardsData.amount");
    assertEq(actual_.rewardPoolId, expected_.rewardPoolId, "PreviewClaimableRewardsData.rewardPoolId");
  }
}
