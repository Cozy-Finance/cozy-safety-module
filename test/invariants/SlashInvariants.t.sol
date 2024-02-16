// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, ReservePool} from "../../src/lib/structs/Pools.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {Slash} from "../../src/lib/structs/Slash.sol";
import {Trigger} from "../../src/lib/structs/Trigger.sol";
import {TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {IStateChangerErrors} from "../../src/interfaces/IStateChangerErrors.sol";
import {MockTrigger} from "../utils/MockTrigger.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract StateTransitionInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  using FixedPointMathLib for uint256;

  mapping(IERC20 => uint256) expectedAssetSlashAmounts;
  mapping(IERC20 => uint256) assetPoolsBeforeSlash;

  function invariant_slashAccountingUpdates() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger selectedTrigger_ = safetyModuleHandler.pickValidTrigger(_randomUint256());
    // If there are no valid triggers, we skip this invariant.
    if (selectedTrigger_ == ITrigger(safetyModuleHandler.DEFAULT_ADDRESS())) return;
    Trigger memory selectedTriggerData_ = safetyModule.triggerData(selectedTrigger_);
    // Trigger the trigger.
    MockTrigger(address(selectedTrigger_)).mockState(TriggerState.TRIGGERED);

    // Trigger the safety module putting it in triggered or paused state.
    safetyModule.trigger(selectedTrigger_);

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) return;

    Slash[] memory slashes_ = new Slash[](numReservePools);
    uint256[] memory reservePoolDepositAmountsBeforeSlash_ = new uint256[](numReservePools);
    for (uint8 i = 0; i < numReservePools; i++) {
      ReservePool memory reservePool_ = safetyModule.reservePools(i);
      slashes_[i] = Slash({reservePoolId: i, amount: _pickSlashAmount(i)});
      reservePoolDepositAmountsBeforeSlash_[i] = reservePool_.depositAmount;
      expectedAssetSlashAmounts[reservePool_.asset] += slashes_[i].amount;
    }

    for (uint8 i = 0; i < assets.length; i++) {
      assetPoolsBeforeSlash[assets[i]] = safetyModule.assetPools(assets[i]).amount;
    }

    // Slash the safety module.
    vm.prank(selectedTriggerData_.payoutHandler);
    safetyModule.slash(slashes_, _randomAddress());

    for (uint8 i = 0; i < numReservePools; i++) {
      ReservePool memory reservePool_ = safetyModule.reservePools(i);

      require(
        reservePoolDepositAmountsBeforeSlash_[i] - reservePool_.depositAmount == slashes_[i].amount,
        string.concat(
          "Invariant failed: Reserve pool deposit amount slashed does not equal the amount specified in the slash.",
          " reservePoolDepositAmountsBeforeSlash_[i]: ",
          Strings.toString(reservePoolDepositAmountsBeforeSlash_[i]),
          ", reservePool_.depositAmount: ",
          Strings.toString(reservePool_.depositAmount),
          ", slashes_[i].amount: ",
          Strings.toString(slashes_[i].amount)
        )
      );
    }
    for (uint8 i = 0; i < assets.length; i++) {
      require(
        safetyModule.assetPools(assets[i]).amount
          == assetPoolsBeforeSlash[assets[i]] - expectedAssetSlashAmounts[assets[i]],
        string.concat(
          "Invariant failed: Asset pool amount slashed does not equal the amount specified in the slash.",
          " safetyModule.assetPools(assets[i]).amount: ",
          Strings.toString(safetyModule.assetPools(assets[i]).amount),
          ", assetPoolsBeforeSlash[assets[i]]: ",
          Strings.toString(assetPoolsBeforeSlash[assets[i]]),
          ", expectedAssetSlashAmounts[assets[i]]: ",
          Strings.toString(expectedAssetSlashAmounts[assets[i]])
        )
      );
    }
  }

  function _pickRandomTriggerAndTriggerData() internal view returns (ITrigger, Trigger memory) {
    ITrigger[] memory triggers_ = safetyModuleHandler.getTriggers();
    ITrigger selectedTrigger_ = triggers_[_randomUint256() % triggers_.length];
    return (selectedTrigger_, safetyModule.triggerData(selectedTrigger_));
  }

  function _pickSlashAmount(uint8 reservePoolId_) internal view returns (uint256) {
    ReservePool memory reservePool_ = safetyModule.reservePools(reservePoolId_);
    uint256 slashPercentage_ = bound(_randomUint256() % MathConstants.ZOC, 0, reservePool_.maxSlashPercentage);
    return reservePool_.depositAmount.mulDivDown(slashPercentage_, MathConstants.ZOC);
  }
}

contract SlashInvariantsWithStateTransitionsSingleReservePool is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithSingleReservePool
{}

contract SlashInvariantsWithStateTransitionsMultipleReservePools is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithMultipleReservePools
{}
