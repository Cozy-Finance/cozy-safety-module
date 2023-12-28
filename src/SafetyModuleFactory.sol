// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {UndrippedRewardPoolConfig} from "./lib/structs/Configs.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IManager} from "./interfaces/IManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "./interfaces/ISafetyModuleFactory.sol";

/**
 * @notice Deploys new Safety Modules.
 */
contract SafetyModuleFactory is ISafetyModuleFactory {
  using Clones for address;

  /// @notice Address of the Cozy protocol manager.
  IManager public immutable cozyManager;

  /// @notice Address of the Safety Module logic contract used to deploy new Safety Modules.
  ISafetyModule public immutable safetyModuleLogic;

  /// @dev Thrown when the caller is not authorized to perform the action.
  error Unauthorized();

  /// @dev Thrown if an address parameter is invalid.
  error InvalidAddress();

  /// @param manager_ Cozy protocol Manager.
  /// @param safetyModuleLogic_ Logic contract for deploying new Safety Modules.
  constructor(IManager manager_, ISafetyModule safetyModuleLogic_) {
    _assertAddressNotZero(address(manager_));
    _assertAddressNotZero(address(safetyModuleLogic_));
    cozyManager = manager_;
    safetyModuleLogic = safetyModuleLogic_;
  }

  /// @notice Creates a new Safety Module contract with the specified configuration.
  /// @param owner_ The owner of the safety module.
  /// @param pauser_ The pauser of the safety module.
  /// @param reserveAssets_ Array of reserve pool assets for the safety module.
  /// @param undrippedRewardPoolConfig_ Array of undripped reward pool configurations.
  /// @param unstakeDelay_ Delay before a staker can unstake their assets for the two step unstake process.
  /// @param baseSalt_ Used to compute the resulting address of the set.
  function deploySafetyModule(
    address owner_,
    address pauser_,
    IERC20[] calldata reserveAssets_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfig_,
    uint128 unstakeDelay_,
    bytes32 baseSalt_
  ) public returns (ISafetyModule safetyModule_) {
    // It'd be harmless to let anyone deploy safety modules, but to make it more clear where the proper entry
    // point for safety module creation is, we restrict this to being called by the manager.
    if (msg.sender != address(cozyManager)) revert Unauthorized();

    safetyModule_ = ISafetyModule(address(safetyModuleLogic).cloneDeterministic(salt(baseSalt_)));
    safetyModule_.initialize(owner_, pauser_, reserveAssets_, undrippedRewardPoolConfig_, unstakeDelay_);
    emit SafetyModuleDeployed(safetyModule_, reserveAssets_);
  }

  /// @notice Given the `baseSalt_` compute and return the address that Safety Module will be deployed to.
  /// @dev Safety Module addresses are uniquely determined by their salt because the deployer is always the factory,
  /// and the use of minimal proxies means they all have identical bytecode and therefore an identical bytecode hash.
  /// @dev The `baseSalt_` is the user-provided salt, not the final salt after hashing with the chain ID.
  function computeAddress(bytes32 baseSalt_) external view returns (address) {
    return Clones.predictDeterministicAddress(address(safetyModuleLogic), salt(baseSalt_), address(this));
  }

  /// @notice Given the `baseSalt_`, return the salt that will be used for deployment.
  function salt(bytes32 baseSalt_) public view returns (bytes32) {
    // We take the user-provided salt and concatenate it with the chain ID before hashing. This is
    // required because CREATE2 with a user provided salt or CREATE both make it easy for an
    // attacker to create a malicious Safety Module on one chain and pass it off as a reputable Safety Module from
    // another chain since the two have the same address.
    return keccak256(abi.encode(baseSalt_, block.chainid));
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
