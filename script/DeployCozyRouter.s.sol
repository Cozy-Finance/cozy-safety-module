// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {ICozyManager} from "cozy-safety-module-rewards-manager/interfaces/ICozyManager.sol";
import {IDripModelConstantFactory} from "cozy-safety-module-models/interfaces/IDripModelConstantFactory.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {CozyRouterAvax} from "../src/CozyRouterAvax.sol";
import {CozySafetyModuleManager} from "../src/CozySafetyModuleManager.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../src/SafetyModuleFactory.sol";
import {TriggerFactories} from "../src/lib/structs/TriggerFactories.sol";
import {IChainlinkTriggerFactory} from "../src/interfaces/IChainlinkTriggerFactory.sol";
import {ICozySafetyModuleManager} from "../src/interfaces/ICozySafetyModuleManager.sol";
import {IOwnableTriggerFactory} from "../src/interfaces/IOwnableTriggerFactory.sol";
import {IStETH} from "../src/interfaces/IStETH.sol";
import {IUMATriggerFactory} from "../src/interfaces/IUMATriggerFactory.sol";
import {IWeth} from "../src/interfaces/IWeth.sol";
import {IWstETH} from "../src/interfaces/IWstETH.sol";

/**
 * @notice Purpose: Local deploy, testing, and production.
 *
 * This script deploys a CozyRouter.
 *
 * To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $OPTIMISM_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/DeployCozyRouter.s.sol \
 *   --sig "run(string)" "deploy-router-<test or production>" \
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions with etherscan verification.
 * forge script script/DeployCozyRouter.s.sol \
 *   --sig "run(string)" "deploy-router-<test or production>" \
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --etherscan-api-key $ETHERSCAN_KEY \
 *   --verify \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract DeployCozyRouter is ScriptUtils {
  using stdJson for string;

  // Contracts to define per-network.
  IStETH stEth;
  IWstETH wstEth;
  address wrappedNativeToken;
  ICozySafetyModuleManager safetyModuleCozyManager;
  ICozyManager rewardsManagerCozyManager;
  IChainlinkTriggerFactory chainlinkTriggerFactory;
  IOwnableTriggerFactory ownableTriggerFactory;
  IUMATriggerFactory umaTriggerFactory;
  IDripModelConstantFactory dripModelConstantFactory;

  address router;

  function run(string memory fileName_) public virtual {
    // -------------------------------
    // -------- Configuration --------
    // -------------------------------

    // -------- Load json --------
    string memory json_ = readInput(fileName_);

    // -------- Token Setup --------
    if (block.chainid == 10 || block.chainid == 42_161 || block.chainid == 1) {
      wrappedNativeToken = json_.readAddress(".weth");
      assertToken(IERC20(wrappedNativeToken), "Wrapped Ether", 18);
      console2.log("Using WETH at", address(wrappedNativeToken));
    } else if (block.chainid == 43_114) {
      wrappedNativeToken = json_.readAddress(".wavax");
      assertToken(IERC20(wrappedNativeToken), "Wrapped AVAX", 18);
      console2.log("Using WAVAX at", address(wrappedNativeToken));
    } else {
      revert("Unsupported chain ID");
    }
    // -------- Safety Module Cozy Manager --------
    safetyModuleCozyManager = ICozySafetyModuleManager(json_.readAddress(".safetyModuleCozyManager"));
    console2.log("safetyModuleCozyManager", address(safetyModuleCozyManager));

    // -------- Rewards Manager Cozy Manager --------
    rewardsManagerCozyManager = ICozyManager(json_.readAddress(".rewardsManagerCozyManager"));
    console2.log("rewardsManagerCozyManager", address(rewardsManagerCozyManager));

    // -------- Trigger Factories --------
    chainlinkTriggerFactory = IChainlinkTriggerFactory(json_.readAddress(".chainlinkTriggerFactory"));
    ownableTriggerFactory = IOwnableTriggerFactory(json_.readAddress(".ownableTriggerFactory"));
    umaTriggerFactory = IUMATriggerFactory(json_.readAddress(".umaTriggerFactory"));
    console2.log("chainlinkTriggerFactory", address(chainlinkTriggerFactory));
    console2.log("ownableTriggerFactory", address(ownableTriggerFactory));
    console2.log("umaTriggerFactory", address(umaTriggerFactory));

    // -------- Drip Model Factories --------
    dripModelConstantFactory = IDripModelConstantFactory(json_.readAddress(".dripModelConstantFactory"));
    console2.log("dripModelConstantFactory", address(dripModelConstantFactory));

    // -------- Deploy: CozyRouter --------
    // Different chains have different tokens that may need to be wrapped, so we have chain specific router
    // contracts.
    if (block.chainid == 43_114) {
      vm.broadcast();
      router = address(
        new CozyRouterAvax(
          safetyModuleCozyManager,
          rewardsManagerCozyManager,
          IWeth(wrappedNativeToken), // WAVAX conforms to the same interface as WETH.
          TriggerFactories({
            chainlinkTriggerFactory: chainlinkTriggerFactory,
            ownableTriggerFactory: ownableTriggerFactory,
            umaTriggerFactory: umaTriggerFactory
          }),
          dripModelConstantFactory
        )
      );
      console2.log("CozyRouterAvax deployed", router);
    } else {
      vm.broadcast();
      router = address(
        new CozyRouter(
          safetyModuleCozyManager,
          rewardsManagerCozyManager,
          IWeth(wrappedNativeToken),
          stEth,
          wstEth,
          TriggerFactories({
            chainlinkTriggerFactory: chainlinkTriggerFactory,
            ownableTriggerFactory: ownableTriggerFactory,
            umaTriggerFactory: umaTriggerFactory
          }),
          dripModelConstantFactory
        )
      );
      console2.log("CozyRouter deployed", router);
    }
  }
}
