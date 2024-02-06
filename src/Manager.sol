// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {IDripModel} from "./interfaces/IDripModel.sol";
import {IManager} from "./interfaces/IManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "./interfaces/ISafetyModuleFactory.sol";
import {UpdateConfigsCalldataParams, ReservePoolConfig} from "./lib/structs/Configs.sol";
import {Delays} from "./lib/structs/Delays.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";

contract Manager is Governable, IManager {
  struct DripModelLookup {
    IDripModel dripModel;
    bool exists;
  }

  /// @notice The max number of reserve pools allowed per safety module.
  uint256 public immutable allowedReservePools;

  /// @notice Cozy protocol SafetyModuleFactory.
  ISafetyModuleFactory public immutable safetyModuleFactory;

  /// @notice For the specified set, returns whether it's a valid Cozy Safety Module.
  mapping(ISafetyModule => bool) public isSafetyModule;

  /// @notice The default fee drip model.
  IDripModel public feeDripModel;

  /// @notice Override fee drip models for specific SafetyModules.
  mapping(ISafetyModule => DripModelLookup) public overrideFeeDripModels;

  /// @dev Thrown when an safety module's configuration does not meet all requirements.
  error InvalidConfiguration();

  /// @param owner_ The Cozy protocol owner.
  /// @param pauser_ The Cozy protocol pauser.
  /// @param safetyModuleFactory_ The Cozy protocol SafetyModuleFactory.
  /// @param feeDripModel_ The default fee drip model for all fees.
  /// @param allowedReservePools_ The max number of reserve pools allowed per safety module.
  constructor(
    address owner_,
    address pauser_,
    ISafetyModuleFactory safetyModuleFactory_,
    IDripModel feeDripModel_,
    uint256 allowedReservePools_
  ) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(address(safetyModuleFactory_));
    _assertAddressNotZero(address(feeDripModel_));
    __initGovernable(owner_, pauser_);

    safetyModuleFactory = safetyModuleFactory_;
    allowedReservePools = allowedReservePools_;

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
    overrideFeeDripModels[safetyModule_] = DripModelLookup({exists: true, dripModel: feeDripModel_});
    emit OverrideFeeDripModelUpdated(safetyModule_, feeDripModel_);
  }

  /// @notice Reset the override fee drip model for the specified safety module back to th default.
  /// @param safetyModule_ The safety module to update the fee drip model for.
  function resetOverrideFeeDripModel(ISafetyModule safetyModule_) external onlyOwner {
    delete overrideFeeDripModels[safetyModule_];
    emit OverrideFeeDripModelUpdated(safetyModule_, feeDripModel);
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
  /// @param configs_ The configuration for the safety module.
  /// @param salt_ Used to compute the resulting address of the set.
  function createSafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 salt_
  ) external returns (ISafetyModule safetyModule_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(pauser_);

    if (!ConfiguratorLib.isValidConfiguration(configs_.reservePoolConfigs, configs_.delaysConfig, allowedReservePools))
    {
      revert InvalidConfiguration();
    }

    isSafetyModule[ISafetyModule(safetyModuleFactory.computeAddress(salt_))] = true;
    safetyModule_ = safetyModuleFactory.deploySafetyModule(owner_, pauser_, configs_, salt_);
  }

  function getFeeDripModel(ISafetyModule safetyModule_) external view returns (IDripModel) {
    DripModelLookup memory overrideFeeDripModel_ = overrideFeeDripModels[safetyModule_];
    if (overrideFeeDripModel_.exists) return overrideFeeDripModel_.dripModel;
    else return feeDripModel;
  }

  // ----------------------------------
  // -------- Internal Helpers --------
  // ----------------------------------

  /// @dev Executes the fee drip model update.
  function _updateFeeDripModel(IDripModel feeDripModel_) internal {
    feeDripModel = feeDripModel_;
    emit FeeDripModelUpdated(feeDripModel_);
  }
}
