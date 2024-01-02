// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {UndrippedRewardPool, ReservePool} from "../../src/lib/structs/Pools.sol";
import {UserRewardsData} from "../../src/lib/structs/Rewards.sol";
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
    assertEq(
      actual_.pendingRedemptionsAmount, expected_.pendingRedemptionsAmount, "ReservePool.pendingRedemptionsAmount"
    );
    assertEq(actual_.feeAmount, expected_.feeAmount, "ReservePool.feeAmount");
    assertEq(actual_.rewardsPoolsWeight, expected_.rewardsPoolsWeight, "ReservePool.rewardsPoolsWeight");
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
}
