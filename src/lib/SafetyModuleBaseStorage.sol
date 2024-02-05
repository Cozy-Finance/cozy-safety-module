// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {ReservePool, AssetPool, IdLookup} from "./structs/Pools.sol";
import {Trigger} from "./structs/Trigger.sol";
import {Delays} from "./structs/Delays.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract SafetyModuleBaseStorage {
  /// @dev Reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @dev Used for doing aggregate accounting of reserve assets.
  mapping(IERC20 reserveAsset_ => AssetPool assetPool_) public assetPools;

  /// @dev Maps triggers to trigger data.
  mapping(ITrigger trigger_ => Trigger triggerData_) public triggerData;

  /// @dev Maps payout handlers to payout handler data.
  mapping(address payoutHandler_ => uint256 numPendingSlashes_) public payoutHandlerNumPendingSlashes;

  /// @dev Config, withdrawal and unstake delays.
  Delays public delays;

  /// @notice The state of this SafetyModule.
  SafetyModuleState public safetyModuleState;

  /// @notice The number of slashes that must occur before the safety module can be active.
  /// @dev This value is incremented when a trigger occurs, and decremented when a slash from a trigger assigned payout
  /// handler occurs. When this value is non-zero, the safety module is triggered (or paused).
  uint16 public numPendingSlashes;

  /// @dev Has config for deposit fee and where to send fees
  IManager public immutable cozyManager;

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  IReceiptTokenFactory public immutable receiptTokenFactory;
}
