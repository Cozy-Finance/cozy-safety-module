// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ICozyManager} from "cozy-safety-module-rewards-manager/interfaces/ICozyManager.sol";
import {IRewardsManager} from "cozy-safety-module-rewards-manager/interfaces/IRewardsManager.sol";
import {StakePoolConfig, RewardPoolConfig} from "cozy-safety-module-rewards-manager/lib/structs/Configs.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract RewardsManagerDeploymentHelpers is CozyRouterCommon {
  /// @notice Deploys a new Rewards Manager.
  function deployRewardsManager(
    ICozyManager rewardsManagerCozyManager_,
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external payable returns (IRewardsManager rewardsManager_) {
    rewardsManager_ =
      rewardsManagerCozyManager_.createRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, salt_);
  }
}
