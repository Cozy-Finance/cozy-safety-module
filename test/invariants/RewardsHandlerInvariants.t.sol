// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleReservePoolAndSingleRewardPool,
  InvariantTestWithMultipleReservePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract RewardsHandlerInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_userRewardsAccountingAfterClaimRewards() public syncCurrentTimestamp(safetyModuleHandler) {
    address actor_ = safetyModuleHandler.claimRewards(_randomAddress(), _randomUint256());
  }
}

contract RewardsHandlerInvariantsSingleReservePoolSingleRewardPool is
  RewardsHandlerInvariants,
  InvariantTestWithSingleReservePoolAndSingleRewardPool
{}

contract RewardsHandlerInvariantsMultipleReservePoolsMultipleRewardPools is
  RewardsHandlerInvariants,
  InvariantTestWithMultipleReservePoolsAndMultipleRewardPools
{}
