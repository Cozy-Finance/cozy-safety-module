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
import {TriggerConfig, TriggerMetadata} from "../src/lib/structs/Trigger.sol";
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
contract DeployUnionSafetyModule is ScriptUtils {
  using stdJson for string;

  CozyRouter router = CozyRouter(address(0));
  ITrigger deployedTrigger;

  struct TriggerMetadata {
    // A human-readable description of the trigger.
    string description;
    // Any extra data that should be included in the trigger's metadata.
    string extraData;
    // The URI of a logo image to represent the trigger.
    string logoURI;
    // The name that should be used for SafetyModules that use the trigger.
    string name;
  }

  function deployTrigger(string memory fileName_) public virtual {
    // -------- Load json --------
    string memory json_ = readInput(fileName_);

    // -------------------------------------
    // ----------- Deploy Trigger ----------
    // -------------------------------------
    address triggerOwner_ = json_.readAddress(".triggerOwner");
    TriggerMetadata memory triggerMetadata_ = abi.decode(_json.parseRaw(".triggerMetadata"), (TriggerMetadata));
    bytes32 triggerSalt_ = json_.readBytes32(".triggerSalt");

    console2.log("Deploying OwnableTrigger...");
    console2.log("    triggerOwner", triggerOwner_);
    console2.log("    triggerDescription", triggerMetadata_.description);
    console2.log("    triggerExtraData", triggerMetadata_.extraData);
    console2.log("    triggerLogoURI", triggerMetadata_.logoURI);
    console2.log("    triggerName", triggerMetadata_.name);
    console2.log("    triggerSalt", triggerSalt_);

    require(triggerOwner_ != address(0), "Trigger owner cannot be zero address");

    vm.broadcast();
    deployedTrigger = router.deployOwnableTrigger(triggerOwner_, triggerMetadata_, triggerSalt_);

    console2.log("OwnableTrigger deployed", address(deployedTrigger));
    console2.log("========");
  }

  function deploySafetyModule(string memory fileName_) public virtual {
    // -------- Load json --------
    string memory json_ = readInput(fileName_);

    // -------------------------------------
    // ------ Deploy SafetyModule ----------
    // -------------------------------------
    address safetyModuleOwner_ = json_.readAddress(".safetyModuleOwner");
    address safetyModulePauser_ = json_.readAddress(".safetyModulePauser");
    bytes32 safetyModuleSalt_ = json_.readBytes32(".safetyModuleSalt");

    address reservePoolAsset_ = json_.readAddress(".reservePoolAsset");
    uint256 reservePoolMaxSlashPercentage_ = json_.readUint(".reservePoolMaxSlashPercentage");
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig(reservePoolMaxSlashPercentage_, IERC20(reservePoolAsset_));

    address payoutHandler_ = json_.readAddress(".payoutHandler");
    TriggerConfig[] memory triggerConfigs_ = new TriggerConfig[](1);
    triggerConfigs_[0] = TriggerConfig(deployedTrigger, payoutHandler_, true);

    Delays memory delays_ = abi.decode(_json.parseRaw(".delays"), (Delays));

    UpdateConfigsCalldataParams memory configs_ =
      UpdateConfigsCalldataParams(reservePoolConfigs_, triggerConfigs_, delays_);

    console.log("Deploying SafetyModule...");
    console2.log("    safetyModuleOwner", safetyModuleOwner_);
    console2.log("    safetyModulePauser", safetyModulePauser_);
    console2.log("    reservePoolAsset", reservePoolAsset_);
    console2.log("    reservePoolMaxSlashPercentage", reservePoolMaxSlashPercentage_);
    console2.log("    triggerPayoutHandler", payoutHandler_);
    console2.log("    triggerAddress", address(deployedTrigger));
    console2.log("    delaysConfigUpdateDelay", delays_.configUpdateDelay);
    console2.log("    delaysConfigUpdateGracePeriod", delays_.configUpdateGracePeriod);
    console2.log("    delaysWithdrawDelay", delays_.withdrawDelay);
    console2.log("    safetyModuleSalt", safetyModuleSalt_);

    vm.broadcast();
    ISafetyModule safetyModule =
      router.deploySafetyModule(safetyModuleOwner_, safetyModulePauser_, configs_, safetyModuleSalt_);

    console2.log("SafetyModule deployed", address(safetyModule));
    console2.log("========");
  }
}
