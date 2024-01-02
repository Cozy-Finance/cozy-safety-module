// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {UndrippedRewardPoolConfig} from "./lib/structs/Configs.sol";
import {IManager} from "./interfaces/IManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "./interfaces/ISafetyModuleFactory.sol";
import {UndrippedRewardPoolConfig, ReservePoolConfig} from "./lib/structs/Configs.sol";
import {Delays} from "./lib/structs/Delays.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {Governable} from "./lib/Governable.sol";

contract Manager is Governable, IManager {
  /// @notice Cozy protocol SafetyModuleFactory.
  ISafetyModuleFactory public immutable safetyModuleFactory;

  /// @notice For the specified set, returns whether it's a valid Cozy Safety Module.
  mapping(ISafetyModule => bool) public isSafetyModule;

  /// @dev Thrown when an safety module's configuration does not meet all requirements.
  error InvalidConfiguration();

  /// @param owner_ The Cozy protocol owner.
  /// @param pauser_ The Cozy protocol pauser.
  /// @param safetyModuleFactory_ The Cozy protocol SafetyModuleFactory.
  constructor(address owner_, address pauser_, ISafetyModuleFactory safetyModuleFactory_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(address(safetyModuleFactory_));
    __initGovernable(owner_, pauser_);

    safetyModuleFactory = safetyModuleFactory_;

    // TODO: Allowed reserve and reward pools per set
    // allowedMarketsPerSet = allowedMarketsPerSet_;

    // TODO: Set fees and delays
    // _updateFees(fees_);
    // _updateDelays(delays_);
  }

  function claimCozyFees(IERC20[] memory asset_, address receiver_) external returns (uint256 amount_) {}

  /// @notice Batch pauses safetyModules_. The manager's pauser or owner can perform this action.
  function pause(ISafetyModule[] calldata safetyModules_) external {
    if (msg.sender != pauser && msg.sender != owner) revert Unauthorized();
    for (uint256 i = 0; i < safetyModules_.length; i++) {
      safetyModules_[i].pause();
    }
  }

  /// @notice Batch unpauses sets_. The manager's owner can perform this action.
  function unpause(ISafetyModule[] calldata safetyModules_) external onlyOwner {
    for (uint256 i = 0; i < safetyModules_.length; i++) {
      safetyModules_[i].unpause();
    }
  }

  // ----------------------------------------
  // -------- Permissionless Actions --------
  // ----------------------------------------

  /// @notice Deploys a new Safety Module with the provided parameters.
  /// @param owner_ The owner of the safety module.
  /// @param pauser_ The pauser of the safety module.
  /// @param reservePoolConfigs_ The array of reserve pool configs for the safety module.
  /// @param undrippedRewardPoolConfigs_ The array of undripped reward pool configs for the safety module.
  /// @param delaysConfig_ The delays config for the safety module.
  /// @param salt_ Used to compute the resulting address of the set.
  function createSafetyModule(
    address owner_,
    address pauser_,
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_,
    bytes32 salt_
  ) external returns (ISafetyModule safetyModule_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(pauser_);

    if (!ConfiguratorLib.isValidConfiguration(reservePoolConfigs_, delaysConfig_)) revert InvalidConfiguration();

    isSafetyModule[ISafetyModule(safetyModuleFactory.computeAddress(salt_))] = true;
    safetyModule_ = safetyModuleFactory.deploySafetyModule(
      owner_, pauser_, reservePoolConfigs_, undrippedRewardPoolConfigs_, delaysConfig_, salt_
    );
  }
}
