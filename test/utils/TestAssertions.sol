// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {UndrippedRewardPool} from "../../src/lib/structs/Pools.sol";
import {UserRewardsData} from "../../src/lib/structs/Rewards.sol";
import {SafetyModuleState, TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {Test} from "forge-std/Test.sol";

abstract contract TestAssertions is Test {
  function assertEq(uint256[][] memory actual_, uint256[][] memory expected_) internal {
    assertEq(actual_.length, expected_.length);
    for (uint256 i = 0; i < actual_.length; i++) {
      assertEq(actual_[i], expected_[i]);
    }
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
}
