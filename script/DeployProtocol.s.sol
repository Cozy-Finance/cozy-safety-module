// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {CozySafetyModuleManager} from "../src/CozySafetyModuleManager.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../src/SafetyModuleFactory.sol";
import {ReservePoolConfig, TriggerConfig, UpdateConfigsCalldataParams} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {IChainlinkTriggerFactory} from "../src/interfaces/IChainlinkTriggerFactory.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
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
 *        5. (4)  Deploy: DepositToken logic
 *        6. (5)  Transaction: DepositToken logic initialization
 *        7. (6)  Deploy: StkToken logic
 *        8. (7)  Transaction: StkToken logic initialization
 *        9. (8)  Deploy: ReceiptTokenFactory
 *   3. Deploy all peripheral contracts:
 *        1. (9)  Deploy: CozyRouter
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
  IChainlinkTriggerFactory chainlinkTriggerFactory;
  IOwnableTriggerFactory ownableTriggerFactory;
  IUMATriggerFactory umaTriggerFactory;
  IDripModel feeDripModel;

  // Core contracts to deploy.
  CozySafetyModuleManager manager;
  SafetyModule safetyModuleLogic;
  SafetyModuleFactory safetyModuleFactory;
  ReceiptToken depositTokenLogic;
  // StkToken stkTokenLogic; TODO: Deploy and initialize stkTokenLogic.
  ReceiptTokenFactory receiptTokenFactory;

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

    // -------- Trigger Factories --------
    chainlinkTriggerFactory = IChainlinkTriggerFactory(json_.readAddress(".chainlinkTriggerFactory"));
    ownableTriggerFactory = IOwnableTriggerFactory(json_.readAddress(".ownableTriggerFactory"));
    umaTriggerFactory = IUMATriggerFactory(json_.readAddress(".umaTriggerFactory"));

    // -------- Fee Drip Model --------
    feeDripModel = IDripModel(json_.readAddress(".feeDripModel"));

    // -------- Reserve Pool Limits --------
    allowedReservePools = uint8(json_.readUint(".allowedReservePools"));

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
    IReceiptToken computedAddrDepositTokenLogic_ = IReceiptToken(vm.computeCreateAddress(msg.sender, nonce_ + 4));
    // nonce + 5 is initialization of the DepositToken logic.
    // TODO Deploy an init stkTokenLogic.
    // IReceiptToken computedAddrStkTokenLogic_ = IReceiptToken(vm.computeCreateAddress(msg.sender, nonce_ + 6));
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(msg.sender, nonce_ + 6));

    // ------------------------------------------
    // -------- Core Protocol Deployment --------
    // ------------------------------------------

    // -------- Deploy: CozySafetyModuleManager --------
    vm.broadcast();
    manager =
      new CozySafetyModuleManager(owner, pauser, computedAddrSafetyModuleFactory_, feeDripModel, allowedReservePools);
    console2.log("CozySafetyModuleManager deployed:", address(manager));
    require(address(manager) == address(computedAddrManager_), "CozySafetyModuleManager address mismatch");

    // -------- Deploy: SafetyModule Logic --------
    vm.broadcast();
    safetyModuleLogic = new SafetyModule(computedAddrManager_, computedAddrReceiptTokenFactory_);
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

    // -------- Deploy: DepositToken Logic --------
    vm.broadcast();
    depositTokenLogic = new ReceiptToken();
    console2.log("DepositToken logic deployed:", address(depositTokenLogic));
    require(
      address(depositTokenLogic) == address(computedAddrDepositTokenLogic_), "DepositToken logic address mismatch"
    );

    vm.broadcast();
    depositTokenLogic.initialize(address(0), "", "", 0);

    // TODO: Deploy StkToken logic and initialize
    // -------- Deploy: StkToken Logic --------
    // vm.broadcast();
    // stkTokenLogic = new StkToken();
    // console2.log("StkToken logic deployed:", address(stkTokenLogic));
    // require(address(stkTokenLogic) == address(computedAddrStkTokenLogic_), "StkToken logic address mismatch");

    // vm.broadcast();
    // stkTokenLogic.initialize(ISafetyModule(address(0)), "", "", 0);

    // -------- Deploy: ReceiptTokenFactory --------
    vm.broadcast();
    // TODO: Use computed stk token logic address.
    receiptTokenFactory = new ReceiptTokenFactory(computedAddrDepositTokenLogic_, IReceiptToken(address(0)));
    console2.log("ReceiptTokenFactory deployed:", address(receiptTokenFactory));
    require(
      address(receiptTokenFactory) == address(computedAddrReceiptTokenFactory_), "ReceiptTokenFactory address mismatch"
    );

    // ----------------------------------------
    // -------- Peripheral Deployments --------
    // ----------------------------------------

    // -------- Deploy: CozyRouter --------
    vm.broadcast();
    router = new CozyRouter(
      computedAddrManager_, weth, stEth, wstEth, chainlinkTriggerFactory, ownableTriggerFactory, umaTriggerFactory
    );
    console2.log("CozyRouter deployed", address(router));
  }
}
