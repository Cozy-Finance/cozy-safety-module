// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IDripModel} from "./IDripModel.sol";
import {ISafetyModule} from "./ISafetyModule.sol";

/**
 * @dev Data types and events for the Manager.
 */
interface IManagerEvents {
  /// @dev Emitted when accrued Cozy reserve fees and backstop fees are swept from a Set to the Cozy owner (for
  /// reserves) and backstop.
  event CozyFeesClaimed(address indexed set_, uint128 reserveAmount_, uint128 backstopAmount_);

  /// @dev Emitted when the default fee drip model is updated by the Cozy owner.
  event FeeDripModelUpdated(IDripModel indexed feeDripModel_);

  /// @dev Emitted when an override fee drip model is updated by the Cozy owner.
  event OverrideFeeDripModelUpdated(ISafetyModule indexed safetyModule_, IDripModel indexed feeDripModel_);
}
