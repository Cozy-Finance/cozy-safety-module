// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleState} from "./SafetyModuleStates.sol";

/// @dev Enum representing what the caller of a function is.
/// NONE indicates that the caller has no authorization privileges.
/// OWNER indicates that the caller is the owner of the SafetyModule.
/// PAUSER indicates that the caller is the pauser of the SafetyModule.
/// MANAGER indicates that the caller is the manager of the SafetyModule.
enum CallerRole {
  NONE,
  OWNER,
  PAUSER,
  MANAGER
}

library StateTransitionsLib {
  /// @notice Returns true if the state transition from `from_` to `to_` is valid when called
  /// by `role_`, false otherwise.
  /// @param role_ The CallerRole for the state transition.
  /// @param to_ The SafetyModuleState that is being transitioned to.
  /// @param from_ The SafetyModuleState that is being transitioned from.
  /// @param nonZeroPendingSlashes_ True if the number of pending slashes >= 1.
  function isValidStateTransition(
    CallerRole role_,
    SafetyModuleState to_,
    SafetyModuleState from_,
    bool nonZeroPendingSlashes_
  ) public pure returns (bool) {
    // STATE TRANSITION RULES FOR SAFETY MODULES.
    // To read the below table:
    //   - Rows headers are the "from" state,
    //   - Column headers are the "to" state.
    //   - Cells describe whether that transition is allowed.
    //   - Numbers in parentheses indicate conditional transitions with details described in footnotes.
    //   - Letters in parentheses indicate who can perform the transition with details described in footnotes.
    //
    // | From / To | ACTIVE      | TRIGGERED   | PAUSED   |
    // | --------- | ----------- | ----------- | -------- |
    // | ACTIVE    | -           | true (1)    | true (P) |
    // | TRIGGERED | true (0)    | -           | true (P) |
    // | PAUSED    | true (0, A) | true (1, A) | -        |
    //
    // (0) Only allowed if number of pending slashes == 0.
    // (1) Only allowed if number of pending slashes >= 1.
    // (A) Only allowed if msg.sender is the owner or the manager.
    // (P) Only allowed if msg.sender is the owner, pauser, or manager.

    // The TRIGGERED-ACTIVE cell logic is checked in SlashHandler.slash and does not need to be checked here.
    // The ACTIVE-TRIGGERED cell logic is checked in StateChanger.trigger and does not need to be checked here.
    if (to_ == from_) return false;
    if (role_ == CallerRole.NONE) return false;

    return
    // The PAUSED column.
    (
      to_ == SafetyModuleState.PAUSED
        && (role_ == CallerRole.OWNER || role_ == CallerRole.PAUSER || role_ == CallerRole.MANAGER)
    )
    // The PAUSED-ACTIVE cell.
    || (
      from_ == SafetyModuleState.PAUSED && to_ == SafetyModuleState.ACTIVE && !nonZeroPendingSlashes_
        && (role_ == CallerRole.OWNER || role_ == CallerRole.MANAGER)
    )
    // The PAUSED-TRIGGERED cell.
    || (
      from_ == SafetyModuleState.PAUSED && to_ == SafetyModuleState.TRIGGERED && nonZeroPendingSlashes_
        && (role_ == CallerRole.OWNER || role_ == CallerRole.MANAGER)
    );
  }
}
