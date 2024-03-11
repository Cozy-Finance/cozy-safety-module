// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {ICozySafetyModuleManager} from "./interfaces/ICozySafetyModuleManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "./interfaces/ISafetyModuleFactory.sol";
import {UpdateConfigsCalldataParams, ReservePoolConfig} from "./lib/structs/Configs.sol";
import {Delays} from "./lib/structs/Delays.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";

contract CozySafetyModuleManager is Governable, ICozySafetyModuleManager {
  struct DripModelLookup {
    IDripModel dripModel;
    bool exists;
  }

  /// @notice The max number of reserve pools allowed per SafetyModule.
  uint8 public immutable allowedReservePools;

  /// @notice Cozy Safety Module protocol SafetyModuleFactory.
  ISafetyModuleFactory public immutable safetyModuleFactory;

  /// @notice The default fee drip model used for SafetyModules.
  IDripModel public feeDripModel;

  /// @notice Override fee drip models for specific SafetyModules.
  mapping(ISafetyModule => DripModelLookup) public overrideFeeDripModels;

  /// @notice For the specified SafetyModule, returns whether it's a valid Cozy Safety Module.
  mapping(ISafetyModule => bool) public isSafetyModule;

  /// @dev Thrown when an SafetyModule's configuration does not meet all requirements.
  error InvalidConfiguration();

  /// @param owner_ The Cozy Safety Module protocol owner.
  /// @param pauser_ The Cozy Safety Module protocol pauser.
  /// @param safetyModuleFactory_ The Cozy Safety Module protocol SafetyModuleFactory.
  /// @param feeDripModel_ The default fee drip model used for SafetyModules.
  /// @param allowedReservePools_ The max number of reserve pools allowed per SafetyModule.
  constructor(
    address owner_,
    address pauser_,
    ISafetyModuleFactory safetyModuleFactory_,
    IDripModel feeDripModel_,
    uint8 allowedReservePools_
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

  /// @notice Update the default fee drip model used for SafetyModules.
  /// @param feeDripModel_ The new default fee drip model.
  function updateFeeDripModel(IDripModel feeDripModel_) external onlyOwner {
    _updateFeeDripModel(feeDripModel_);
  }

  /// @notice Update the fee drip model for the specified SafetyModule.
  /// @param safetyModule_ The SafetyModule to update the fee drip model for.
  /// @param feeDripModel_ The new fee drip model for the SafetyModule.
  function updateOverrideFeeDripModel(ISafetyModule safetyModule_, IDripModel feeDripModel_) external onlyOwner {
    overrideFeeDripModels[safetyModule_] = DripModelLookup({exists: true, dripModel: feeDripModel_});
    emit OverrideFeeDripModelUpdated(safetyModule_, feeDripModel_);
  }

  /// @notice Reset the override fee drip model for the specified SafetyModule back to the default.
  /// @param safetyModule_ The SafetyModule to update the fee drip model for.
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

  /// @notice Batch pauses `safetyModules_`. The CozySafetyModuleManager's pauser or owner can perform this action.
  function pause(ISafetyModule[] calldata safetyModules_) external {
    if (msg.sender != pauser && msg.sender != owner) revert Unauthorized();
    for (uint256 i = 0; i < safetyModules_.length; i++) {
      safetyModules_[i].pause();
    }
  }

  /// @notice Batch unpauses `safetyModules_`. The CozySafetyModuleManager's owner can perform this action.
  function unpause(ISafetyModule[] calldata safetyModules_) external onlyOwner {
    for (uint256 i = 0; i < safetyModules_.length; i++) {
      safetyModules_[i].unpause();
    }
  }

  // ----------------------------------------
  // -------- Permissionless Actions --------
  // ----------------------------------------

  /// @notice Deploys a new SafetyModule with the provided parameters.
  /// @param owner_ The owner of the SafetyModule.
  /// @param pauser_ The pauser of the SafetyModule.
  /// @param configs_ The configuration for the SafetyModule.
  /// @param salt_ Used to compute the resulting address of the SafetyModule.
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

    bytes32 deploySalt_ = _computeDeploySalt(msg.sender, salt_);

    ISafetyModuleFactory safetyModuleFactory_ = safetyModuleFactory;
    isSafetyModule[ISafetyModule(safetyModuleFactory_.computeAddress(deploySalt_))] = true;
    safetyModule_ = safetyModuleFactory_.deploySafetyModule(owner_, pauser_, configs_, deploySalt_);
  }

  /// @notice Given a `caller_` and `salt_`, compute and return the address of the SafetyModule deployed with
  /// `createSafetyModule`.
  /// @param caller_ The caller of the `createSafetyModule` function.
  /// @param salt_ Used to compute the resulting address of the SafetyModule along with `caller_`.
  function computeSafetyModuleAddress(address caller_, bytes32 salt_) external view returns (address) {
    bytes32 deploySalt_ = _computeDeploySalt(caller_, salt_);
    return safetyModuleFactory.computeAddress(deploySalt_);
  }

  /// @notice For the specified SafetyModule, returns the drip model used for fee accrual.
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

  /// @notice Given a `caller_` and `salt_`, return the salt used to compute the SafetyModule address deployed from
  /// the `safetyModuleFactory`.
  /// @param caller_ The caller of the `createSafetyModule` function.
  /// @param salt_ Used to compute the resulting address of the SafetyModule along with `caller_`.
  function _computeDeploySalt(address caller_, bytes32 salt_) internal pure returns (bytes32) {
    // To avoid front-running of SafetyModule deploys, msg.sender is used for the deploy salt.
    return keccak256(abi.encodePacked(salt_, caller_));
  }
}
