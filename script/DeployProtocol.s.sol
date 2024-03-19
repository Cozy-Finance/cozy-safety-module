// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ICozyManager} from "cozy-safety-module-rewards-manager/interfaces/ICozyManager.sol";
import {IDripModelConstantFactory} from "cozy-safety-module-models/interfaces/IDripModelConstantFactory.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {CozySafetyModuleManager} from "../src/CozySafetyModuleManager.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../src/SafetyModuleFactory.sol";
import {ReservePoolConfig, TriggerConfig, UpdateConfigsCalldataParams} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {TriggerFactories} from "../src/lib/structs/TriggerFactories.sol";
import {IChainlinkTriggerFactory} from "../src/interfaces/IChainlinkTriggerFactory.sol";
import {ICozySafetyModuleManager} from "../src/interfaces/ICozySafetyModuleManager.sol";
import {IOwnableTriggerFactory} from "../src/interfaces/IOwnableTriggerFactory.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "../src/interfaces/ISafetyModuleFactory.sol";
import {IStETH} from "../src/interfaces/IStETH.sol";
import {IUMATriggerFactory} from "../src/interfaces/IUMATriggerFactory.sol";
import {IWeth} from "../src/interfaces/IWeth.sol";
import {IWstETH} from "../src/interfaces/IWstETH.sol";

/**
 * @dev Deploy procedure is below. Numbers in parenthesis represent the transaction count which can be used
 * to infer the nonce of that deploy.
 *   1. Pre-compute addresses.
 *   2. Deploy the core protocol:
 *        1. (0)  Deploy: Manager
 *        2. (1)  Deploy: SafetyModule logic
 *        3. (2)  Transaction: SafetyModule logic initialization
 *        4. (3)  Deploy: SafetyModuleFactory
 *   3. Deploy all peripheral contracts:
 *        1. (4)  Deploy: CozyRouter
 *
 * To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $OPTIMISM_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/DeployProtocol.s.sol \
 *   --sig "run(string)" "deploy-protocol-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions.
 * forge script script/DeployProtocol.s.sol \
 *   --sig "run(string)" "deploy-protocol-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract DeployProtocol is ScriptUtils {
  using stdJson for string;

  // Owner and pauser are configured per-network.
  address owner;
  address pauser;

  // Global restrictions on the number of reserve and reward pools.
  uint8 allowedReservePools;

  // Contracts to define per-network.
  IERC20 asset;
  IStETH stEth;
  IWstETH wstEth;
  IWeth weth;
  ICozyManager rewardsManagerCozyManager;
  IChainlinkTriggerFactory chainlinkTriggerFactory;
  IOwnableTriggerFactory ownableTriggerFactory;
  IUMATriggerFactory umaTriggerFactory;
  IDripModelConstantFactory dripModelConstantFactory;
  IDripModel feeDripModel;
  IReceiptTokenFactory receiptTokenFactory;

  // Core contracts to deploy.
  CozySafetyModuleManager safetyModuleCozyManager;
  SafetyModule safetyModuleLogic;
  SafetyModuleFactory safetyModuleFactory;

  // Peripheral contracts to deploy.
  CozyRouter router;

  function run(string memory fileName_) public virtual {
    // -------------------------------
    // -------- Configuration --------
    // -------------------------------

    // -------- Load json --------
    string memory json_ = readInput(fileName_);

    // -------- Authentication --------
    owner = json_.readAddress(".owner");
    pauser = json_.readAddress(".pauser");

    // -------- Token Setup --------
    if (block.chainid == 10) {
      asset = IERC20(json_.readAddress(".usdc"));
      assertToken(asset, "USD Coin", 6);

      weth = IWeth(json_.readAddress(".weth"));
      assertToken(IERC20(address(weth)), "Wrapped Ether", 18);
    } else {
      revert("Unsupported chain ID");
    }

    console2.log("Using WETH at", address(weth));
    console2.log("Using USDC at", address(asset));

    // -------- Rewards Manager Cozy Manager --------
    rewardsManagerCozyManager = ICozyManager(json_.readAddress(".rewardsManagerCozyManager"));

    // -------- Trigger Factories --------
    chainlinkTriggerFactory = IChainlinkTriggerFactory(json_.readAddress(".chainlinkTriggerFactory"));
    ownableTriggerFactory = IOwnableTriggerFactory(json_.readAddress(".ownableTriggerFactory"));
    umaTriggerFactory = IUMATriggerFactory(json_.readAddress(".umaTriggerFactory"));

    // -------- Drip Model Factories --------
    dripModelConstantFactory = IDripModelConstantFactory(json_.readAddress(".dripModelConstantFactory"));

    // -------- Fee Drip Model --------
    feeDripModel = IDripModel(json_.readAddress(".feeDripModel"));

    // -------- Reserve Pool Limits --------
    allowedReservePools = uint8(json_.readUint(".allowedReservePools"));

    // -------- Receipt Token Factory --------
    receiptTokenFactory = IReceiptTokenFactory(json_.readAddress(".receiptTokenFactory"));

    // -------------------------------------
    // -------- Address Computation --------
    // -------------------------------------

    uint256 nonce_ = vm.getNonce(msg.sender);
    ICozySafetyModuleManager computedAddrManager_ =
      ICozySafetyModuleManager(vm.computeCreateAddress(msg.sender, nonce_));
    ISafetyModule computedAddrSafetyModuleLogic_ = ISafetyModule(vm.computeCreateAddress(msg.sender, nonce_ + 1));
    // nonce + 2 is initialization of the SafetyModule logic.
    ISafetyModuleFactory computedAddrSafetyModuleFactory_ =
      ISafetyModuleFactory(vm.computeCreateAddress(msg.sender, nonce_ + 3));

    // ------------------------------------------
    // -------- Core Protocol Deployment --------
    // ------------------------------------------

    // -------- Deploy: CozySafetyModuleManager --------
    vm.broadcast();
    safetyModuleCozyManager =
      new CozySafetyModuleManager(owner, pauser, computedAddrSafetyModuleFactory_, feeDripModel, allowedReservePools);
    console2.log("CozySafetyModuleManager deployed:", address(safetyModuleCozyManager));
    require(address(safetyModuleCozyManager) == address(computedAddrManager_), "CozySafetyModuleManager address mismatch");

    // -------- Deploy: SafetyModule Logic --------
    vm.broadcast();
    safetyModuleLogic = new SafetyModule(computedAddrManager_, receiptTokenFactory);
    console2.log("SafetyModule logic deployed:", address(safetyModuleLogic));
    require(
      address(safetyModuleLogic) == address(computedAddrSafetyModuleLogic_), "SafetyModule logic address mismatch"
    );

    vm.broadcast();
    safetyModuleLogic.initialize(
      address(0),
      address(0),
      UpdateConfigsCalldataParams({
        reservePoolConfigs: new ReservePoolConfig[](0),
        triggerConfigUpdates: new TriggerConfig[](0),
        delaysConfig: Delays({configUpdateDelay: 0, configUpdateGracePeriod: 0, withdrawDelay: 0})
      })
    );

    // -------- Deploy: SafetyModuleFactory --------
    vm.broadcast();
    safetyModuleFactory = new SafetyModuleFactory(computedAddrManager_, computedAddrSafetyModuleLogic_);
    console2.log("SafetyModuleFactory deployed:", address(safetyModuleFactory));
    require(
      address(safetyModuleFactory) == address(computedAddrSafetyModuleFactory_), "SafetyModuleFactory address mismatch"
    );

    // ----------------------------------------
    // -------- Peripheral Deployments --------
    // ----------------------------------------

    // -------- Deploy: CozyRouter --------
    vm.broadcast();
    router = new CozyRouter(
      computedAddrManager_,
      rewardsManagerCozyManager,
      weth,
      stEth,
      wstEth,
      TriggerFactories({
        chainlinkTriggerFactory: chainlinkTriggerFactory,
        ownableTriggerFactory: ownableTriggerFactory,
        umaTriggerFactory: umaTriggerFactory
      }),
      dripModelConstantFactory
    );
    console2.log("CozyRouter deployed", address(router));
  }
}
