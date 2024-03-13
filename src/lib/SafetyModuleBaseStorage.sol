// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {ICozySafetyModuleManager} from "../interfaces/ICozySafetyModuleManager.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {ConfigUpdateMetadata} from "./structs/Configs.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {Trigger} from "./structs/Trigger.sol";
import {Delays} from "./structs/Delays.sol";

abstract contract SafetyModuleBaseStorage {
  /// @notice Accounting and metadata for reserve pools configured for this SafetyModule.
  /// @dev Reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @notice The asset pools configured for this SafetyModule.
  /// @dev Used for doing aggregate accounting of reserve assets.
  mapping(IERC20 reserveAsset_ => AssetPool assetPool_) public assetPools;

  /// @notice Maps triggers to trigger related data.
  mapping(ITrigger trigger_ => Trigger triggerData_) public triggerData;

  /// @notice Maps payout handlers to the number of slashes they are currently entitled to.
  /// @dev The number of slashes that a payout handler is entitled to is increased each time a trigger triggers this
  /// SafetyModule, if the payout handler is assigned to the trigger. The number of slashes is decreased each time a
  /// slash from the trigger assigned payout handler occurs.
  mapping(address payoutHandler_ => uint256 numPendingSlashes_) public payoutHandlerNumPendingSlashes;

  /// @notice Config, withdrawal and unstake delays.
  Delays public delays;

  /// @notice Metadata about the most recently queued configuration update.
  ConfigUpdateMetadata public lastConfigUpdate;

  /// @notice The state of this SafetyModule.
  SafetyModuleState public safetyModuleState;

  /// @notice The number of slashes that must occur before the SafetyModule can be active.
  /// @dev This value is incremented when a trigger occurs, and decremented when a slash from a trigger assigned payout
  /// handler occurs. When this value is non-zero, the SafetyModule is triggered (or paused).
  uint16 public numPendingSlashes;

  /// @notice True if the SafetyModule has been initialized.
  bool public initialized;

  /// @dev The Cozy SafetyModule protocol manager contract.
  ICozySafetyModuleManager public immutable cozySafetyModuleManager;

  /// @notice Address of the Cozy SafetyModule protocol ReceiptTokenFactory.
  IReceiptTokenFactory public immutable receiptTokenFactory;
}
