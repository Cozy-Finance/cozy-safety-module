// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {ICozyManager} from "cozy-safety-module-rewards-manager/interfaces/ICozyManager.sol";
import {IRewardsManager} from "cozy-safety-module-rewards-manager/interfaces/IRewardsManager.sol";
import {StakePoolConfig, RewardPoolConfig} from "cozy-safety-module-rewards-manager/lib/structs/Configs.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract RewardsManagerDeploymentHelpers is CozyRouterCommon {
  /// @notice The Cozy Rewards Manager Cozy Manager address.
  ICozyManager public immutable rewardsManagerCozyManager;

  constructor(ICozyManager rewardsManagerCozyManager_) {
    rewardsManagerCozyManager = rewardsManagerCozyManager_;
  }

  /// @notice Deploys a new Rewards Manager.
  function deployRewardsManager(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external payable returns (IRewardsManager rewardsManager_) {
    rewardsManager_ = rewardsManagerCozyManager.createRewardsManager(
      owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, computeSalt(msg.sender, salt_)
    );
  }
}
