// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {UndrippedRewardPoolConfig} from "./lib/structs/Configs.sol";
import {IDripModel} from "./interfaces/IDripModel.sol";
import {IManager} from "./interfaces/IManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "./interfaces/ISafetyModuleFactory.sol";
import {UndrippedRewardPoolConfig, ReservePoolConfig} from "./lib/structs/Configs.sol";
import {Delays} from "./lib/structs/Delays.sol";
import {FeesConfig, DripModelLookup} from "./lib/structs/Manager.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {Governable} from "./lib/Governable.sol";

contract Manager is Governable, IManager {
  /// @notice Cozy protocol SafetyModuleFactory.
  ISafetyModuleFactory public immutable safetyModuleFactory;

  /// @notice For the specified set, returns whether it's a valid Cozy Safety Module.
  mapping(ISafetyModule => bool) public isSafetyModule;

  /// @notice The fees configuration for the Cozy protocol.
  FeesConfig public feesConfig;

  /// @dev Thrown when an safety module's configuration does not meet all requirements.
  error InvalidConfiguration();

  /// @param owner_ The Cozy protocol owner.
  /// @param pauser_ The Cozy protocol pauser.
  /// @param safetyModuleFactory_ The Cozy protocol SafetyModuleFactory.
  /// @param feeDripModel_ The default fee drip model for all fees.
  constructor(address owner_, address pauser_, ISafetyModuleFactory safetyModuleFactory_, IDripModel feeDripModel_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(address(safetyModuleFactory_));
    _assertAddressNotZero(address(feeDripModel_));
    __initGovernable(owner_, pauser_);

    safetyModuleFactory = safetyModuleFactory_;

    // TODO: Allowed reserve and reward pools per set
    // allowedMarketsPerSet = allowedMarketsPerSet_;

    _updateFeeDripModel(feeDripModel_);
  }

  // ------------------------------------
  // -------- Cozy Owner Actions --------
  // ------------------------------------

  /// @notice Update the default fee drip model.
  /// @param feeDripModel_ The new default fee drip model.
  function updateFeeDripModel(IDripModel feeDripModel_) external onlyOwner {
    _updateFeeDripModel(feeDripModel_);
  }

  /// @notice Update the fee drip model for the specified safety module.
  /// @param safetyModule_ The safety module to update the fee drip model for.
  /// @param feeDripModel_ The new fee drip model for the safety module.
  function updateOverrideFeeDripModel(ISafetyModule safetyModule_, IDripModel feeDripModel_) external onlyOwner {
    _updateOverrideFeeDripModel(safetyModule_, feeDripModel_);
  }

  // -----------------------------------------------
  // -------- Batched Safety Module Actions --------
  // -----------------------------------------------

  /// @notice For all specified `safetyModules_`, transfers accrued fees to the owner address.
  function claimFees(ISafetyModule[] calldata safetyModules_) external {
    for (uint256 i = 0; i < safetyModules_.length; i++) {
      safetyModules_[i].claimFees(owner);
      emit ClaimedSafetyModuleFees(safetyModules_[i]);
    }
  }

  /// @notice Batch pauses safetyModules_. The manager's pauser or owner can perform this action.
  function pause(ISafetyModule[] calldata safetyModules_) external {
    if (msg.sender != pauser && msg.sender != owner) revert Unauthorized();
    for (uint256 i = 0; i < safetyModules_.length; i++) {
      safetyModules_[i].pause();
    }
  }

  /// @notice Batch unpauses safetyModules_. The manager's owner can perform this action.
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

  function getFeeDripModel(ISafetyModule safetyModule_) external view returns (IDripModel) {
    DripModelLookup memory overrideFeeDripModel_ = feesConfig.overrideFeeDripModels[safetyModule_];
    if (overrideFeeDripModel_.exists) return overrideFeeDripModel_.dripModel;
    else return feesConfig.feeDripModel;
  }

  // ----------------------------------
  // -------- Internal Helpers --------
  // ----------------------------------

  /// @dev Executes the fee drip model update.
  function _updateFeeDripModel(IDripModel feeDripModel_) internal {
    feesConfig.feeDripModel = feeDripModel_;
    emit FeeDripModelUpdated(feeDripModel_);
  }

  /// @dev Executes the override fee drip model update.
  function _updateOverrideFeeDripModel(ISafetyModule safetyModule_, IDripModel feeDripModel_) internal {
    feesConfig.overrideFeeDripModels[safetyModule_] = DripModelLookup({exists: true, dripModel: feeDripModel_});
    emit OverrideFeeDripModelUpdated(safetyModule_, feeDripModel_);
  }
}
