// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {ReservePoolConfig} from "./lib/structs/Configs.sol";
import {Delays} from "./lib/structs/Delays.sol";
import {UpdateConfigsCalldataParams} from "./lib/structs/Configs.sol";
import {ICozySafetyModuleManager} from "./interfaces/ICozySafetyModuleManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "./interfaces/ISafetyModuleFactory.sol";

/**
 * @notice Deploys new SafetyModules.
 */
contract SafetyModuleFactory is ISafetyModuleFactory {
  using Clones for address;

  /// @notice Address of the Cozy Safety Module protocol manager contract.
  ICozySafetyModuleManager public immutable cozySafetyModuleManager;

  /// @notice Address of the SafetyModule logic contract used to deploy new SafetyModule minimal proxies.
  ISafetyModule public immutable safetyModuleLogic;

  /// @dev Thrown when the caller is not authorized to perform the action.
  error Unauthorized();

  /// @dev Thrown if an address parameter is invalid.
  error InvalidAddress();

  /// @param cozySafetyModuleManager_ Cozy Safety Module protocol manager contract.
  /// @param safetyModuleLogic_ Logic contract for deploying new SafetyModules.
  constructor(ICozySafetyModuleManager cozySafetyModuleManager_, ISafetyModule safetyModuleLogic_) {
    _assertAddressNotZero(address(cozySafetyModuleManager_));
    _assertAddressNotZero(address(safetyModuleLogic_));
    cozySafetyModuleManager = cozySafetyModuleManager_;
    safetyModuleLogic = safetyModuleLogic_;
  }

  /// @notice Deploys a new SafetyModule contract with the specified configuration.
  /// @param owner_ The owner of the SafetyModule.
  /// @param pauser_ The pauser of the SafetyModule.
  /// @param configs_ The configuration for the SafetyModule.
  /// @param baseSalt_ Used to compute the resulting address of the SafetyModule.
  function deploySafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 baseSalt_
  ) public returns (ISafetyModule safetyModule_) {
    // It'd be harmless to let anyone deploy SafetyModules, but to make it more clear where the proper entry
    // point for SafetyModule creation is, we restrict this to being called by the CozySafetyModuleManager.
    if (msg.sender != address(cozySafetyModuleManager)) revert Unauthorized();

    // SafetyModules deployed by this factory are minimal proxies.
    safetyModule_ = ISafetyModule(address(safetyModuleLogic).cloneDeterministic(salt(baseSalt_)));
    safetyModule_.initialize(owner_, pauser_, configs_);

    emit SafetyModuleDeployed(safetyModule_);
  }

  /// @notice Given the `baseSalt_` compute and return the address that SafetyModule will be deployed to.
  /// @dev SafetyModule addresses are uniquely determined by their salt because the deployer is always the factory,
  /// and the use of minimal proxies means they all have identical bytecode and therefore an identical bytecode hash.
  /// @dev The `baseSalt_` is the user-provided salt, not the final salt after hashing with the chain ID.
  /// @param baseSalt_ The user-provided salt.
  function computeAddress(bytes32 baseSalt_) external view returns (address) {
    return Clones.predictDeterministicAddress(address(safetyModuleLogic), salt(baseSalt_), address(this));
  }

  /// @notice Given the `baseSalt_`, return the salt that will be used for deployment.
  /// @param baseSalt_ The user-provided salt.
  function salt(bytes32 baseSalt_) public view returns (bytes32) {
    // We take the user-provided salt and concatenate it with the chain ID before hashing. This is
    // required because CREATE2 with a user provided salt or CREATE both make it easy for an
    // attacker to create a malicious Safety Module on one chain and pass it off as a reputable Safety Module from
    // another chain since the two have the same address.
    return keccak256(abi.encode(baseSalt_, block.chainid));
  }

  /// @notice Revert if the address is the zero address.
  /// @param address_ The address to check.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
