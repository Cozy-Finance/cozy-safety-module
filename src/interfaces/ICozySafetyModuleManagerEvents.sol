// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {ISafetyModule} from "./ISafetyModule.sol";

/**
 * @dev Data types and events for the Manager.
 */
interface ICozySafetyModuleManagerEvents {
  /// @dev Emitted when accrued Cozy fees are swept from a SafetyModule to the Cozy Safety Module protocol owner.
  event ClaimedSafetyModuleFees(ISafetyModule indexed safetyModule_);

  /// @dev Emitted when the default fee drip model is updated by the Cozy Safety Module protocol owner.
  event FeeDripModelUpdated(IDripModel indexed feeDripModel_);

  /// @dev Emitted when an override fee drip model is updated by the Cozy Safety Module protocol owner.
  event OverrideFeeDripModelUpdated(ISafetyModule indexed safetyModule_, IDripModel indexed feeDripModel_);
}
