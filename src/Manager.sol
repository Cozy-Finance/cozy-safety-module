// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {RewardPoolConfig} from "./lib/structs/Configs.sol";
import {IManager} from "./interfaces/IManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "./interfaces/ISafetyModuleFactory.sol";
import {Governable} from "./lib/Governable.sol";

contract Manager is Governable, IManager {
  /// @notice Cozy protocol SafetyModuleFactory.
  ISafetyModuleFactory public immutable safetyModuleFactory;

  /// @notice For the specified set, returns whether it's a valid Cozy Safety Module.
  mapping(ISafetyModule => bool) public isSafetyModule;

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

  // ----------------------------------------
  // -------- Permissionless Actions --------
  // ----------------------------------------

  /// @notice Deploys a new Safety Module with the provided parameters.
  /// @param owner_ The owner of the safety module.
  /// @param pauser_ The pauser of the safety module.
  /// @param reserveAssets_ Array of reserve pool assets for the safety module.
  /// @param rewardPoolConfig_ Array of reward pool configurations.
  /// @param unstakeDelay_ Delay before a staker can unstake their assets for the two step unstake process.
  /// @param salt_ Used to compute the resulting address of the set.
  function createSafetyModule(
    address owner_,
    address pauser_,
    IERC20[] calldata reserveAssets_,
    RewardPoolConfig[] calldata rewardPoolConfig_,
    uint128 unstakeDelay_,
    bytes32 salt_
  ) external returns (ISafetyModule safetyModule_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(pauser_);

    // TODO: Validation of these configs in configurator library.
    // if (!ConfiguratorLib.isValidConfiguration(setConfig_, marketConfigs_, 0, allowedMarketsPerSet)) {
    //   revert InvalidConfiguration();
    // }

    isSafetyModule[ISafetyModule(safetyModuleFactory.computeAddress(salt_))] = true;
    safetyModule_ =
      safetyModuleFactory.deploySafetyModule(owner_, pauser_, reserveAssets_, rewardPoolConfig_, unstakeDelay_, salt_);
  }
}
