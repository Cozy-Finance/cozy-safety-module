// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleState, TriggerState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
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
    assertEq(
      address(actual_.depositReceiptToken), address(expected_.depositReceiptToken), "ReservePool.depositReceiptToken"
    );
    assertEq(actual_.depositAmount, expected_.depositAmount, "ReservePool.depositAmount");
    assertEq(
      actual_.pendingWithdrawalsAmount, expected_.pendingWithdrawalsAmount, "ReservePool.pendingWithdrawalsAmount"
    );
    assertEq(actual_.feeAmount, expected_.feeAmount, "ReservePool.feeAmount");
    assertEq(actual_.maxSlashPercentage, expected_.maxSlashPercentage, "ReservePool.maxSlashPercentage");
  }

  function assertEq(SafetyModuleState actual_, SafetyModuleState expected_) internal {
    assertEq(uint256(actual_), uint256(expected_), "SafetyModuleState");
  }

  function assertEq(TriggerState actual_, TriggerState expected_) internal {
    assertEq(uint256(actual_), uint256(expected_), "TriggerState");
  }
}
