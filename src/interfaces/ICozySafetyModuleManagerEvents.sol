// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IDripModel} from "./IDripModel.sol";
import {ISafetyModule} from "./ISafetyModule.sol";

/**
 * @dev Data types and events for the Manager.
 */
interface ICozySafetyModuleManagerEvents {
  /// @dev Emitted when accrued Cozy fees are swept from a safety module to the Cozy owner.
  event ClaimedSafetyModuleFees(ISafetyModule indexed safetyModule_);

  /// @dev Emitted when the default fee drip model is updated by the Cozy owner.
  event FeeDripModelUpdated(IDripModel indexed feeDripModel_);

  /// @dev Emitted when an override fee drip model is updated by the Cozy owner.
  event OverrideFeeDripModelUpdated(ISafetyModule indexed safetyModule_, IDripModel indexed feeDripModel_);
}
