// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {Manager} from "../src/Manager.sol";
import {ReceiptToken} from "../src/ReceiptToken.sol";
import {ReceiptTokenFactory} from "../src/ReceiptTokenFactory.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../src/SafetyModuleFactory.sol";
import {StkToken} from "../src/StkToken.sol";
import {
  ReservePoolConfig,
  TriggerConfig,
  RewardPoolConfig,
  UpdateConfigsCalldataParams
} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {IChainlinkTriggerFactory} from "../src/interfaces/IChainlinkTriggerFactory.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IOwnableTriggerFactory} from "../src/interfaces/IOwnableTriggerFactory.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
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
  uint256 allowedReservePools;
  uint256 allowedRewardPools;

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
  Manager manager;
  SafetyModule safetyModuleLogic;
  SafetyModuleFactory safetyModuleFactory;
  ReceiptToken depositTokenLogic;
  StkToken stkTokenLogic;
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
    allowedReservePools = json_.readUint(".allowedReservePools");
    allowedRewardPools = json_.readUint(".allowedRewardPools");

    // -------------------------------------
    // -------- Address Computation --------
    // -------------------------------------

    uint256 nonce_ = vm.getNonce(msg.sender);
    IManager computedAddrManager_ = IManager(vm.computeCreateAddress(msg.sender, nonce_));
    ISafetyModule computedAddrSafetyModuleLogic_ = ISafetyModule(vm.computeCreateAddress(msg.sender, nonce_ + 1));
    // nonce + 2 is initialization of the SafetyModule logic.
    ISafetyModuleFactory computedAddrSafetyModuleFactory_ =
      ISafetyModuleFactory(vm.computeCreateAddress(msg.sender, nonce_ + 3));
    IReceiptToken computedAddrDepositTokenLogic_ = IReceiptToken(vm.computeCreateAddress(msg.sender, nonce_ + 4));
    // nonce + 5 is initialization of the DepositToken logic.
    IReceiptToken computedAddrStkTokenLogic_ = IReceiptToken(vm.computeCreateAddress(msg.sender, nonce_ + 6));
    // nonce + 7 is initialization of the StkToken logic.
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(msg.sender, nonce_ + 8));

    // ------------------------------------------
    // -------- Core Protocol Deployment --------
    // ------------------------------------------

    // -------- Deploy: Manager --------
    vm.broadcast();
    manager = new Manager(
      owner, pauser, computedAddrSafetyModuleFactory_, feeDripModel, allowedReservePools, allowedRewardPools
    );
    console2.log("Manager deployed:", address(manager));
    require(address(manager) == address(computedAddrManager_), "Manager address mismatch");

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
        rewardPoolConfigs: new RewardPoolConfig[](0),
        triggerConfigUpdates: new TriggerConfig[](0),
        delaysConfig: Delays({configUpdateDelay: 0, configUpdateGracePeriod: 0, unstakeDelay: 0, withdrawDelay: 0})
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
    depositTokenLogic.initialize(ISafetyModule(address(0)), "", "", 0);

    // -------- Deploy: StkToken Logic --------
    vm.broadcast();
    stkTokenLogic = new StkToken();
    console2.log("StkToken logic deployed:", address(stkTokenLogic));
    require(address(stkTokenLogic) == address(computedAddrStkTokenLogic_), "StkToken logic address mismatch");

    vm.broadcast();
    stkTokenLogic.initialize(ISafetyModule(address(0)), "", "", 0);

    // -------- Deploy: ReceiptTokenFactory --------
    vm.broadcast();
    receiptTokenFactory = new ReceiptTokenFactory(computedAddrDepositTokenLogic_, computedAddrStkTokenLogic_);
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
