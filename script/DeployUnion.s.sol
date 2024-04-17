// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {CozySafetyModuleManager} from "../src/CozySafetyModuleManager.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {TriggerConfig, TriggerMetadata} from "../src/lib/structs/Trigger.sol";
import {ReservePoolConfig, UpdateConfigsCalldataParams} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {IMetadataRegistry} from "../src/interfaces/IMetadataRegistry.sol";
import {IOwnableTriggerFactory} from "../src/interfaces/IOwnableTriggerFactory.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @dev To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $ETH_RPC_URL
 *
 * # Impersonate the Union DAO address and fund address
 * cast rpc --rpc-url "http://127.0.0.1:8545" anvil_impersonateAccount 0xBBD3321f377742c4b3fe458b270c2F271d3294D8
 * cast rpc --rpc-url "http://127.0.0.1:8545" anvil_setBalance 0xBBD3321f377742c4b3fe458b270c2F271d3294D8
 * 10000000000000000000
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/DeployUnion.s.sol \
 *   --sig "run(string)" "deploy-union"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv \
 *   --sender 0xBBD3321f377742c4b3fe458b270c2F271d3294D8 \
 *   --unlocked
 *
 * # Or, to broadcast transactions.
 * forge script script/DeployUnion.s.sol \
 *   --sig "run(string)" "deploy-union"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --broadcast \
 *   -vvvv \
 *   --sender 0xBBD3321f377742c4b3fe458b270c2F271d3294D8 \
 *   --unlocked
 * ```
 */
contract DeployUnion is ScriptUtils {
  using stdJson for string;

  address caller_ = address(0xBBD3321f377742c4b3fe458b270c2F271d3294D8);
  CozyRouter router = CozyRouter(payable(address(0x707C39F1AaA7c8051287b3b231BccAa8CD72138f)));
  CozySafetyModuleManager cozySafetyModuleManager =
    CozySafetyModuleManager(address(0x3cdE8D5148811dDC3F2DEA9caFd73d35BD7A20ab));
  IOwnableTriggerFactory ownableTriggerFactory =
    IOwnableTriggerFactory(address(0xBba03B061CcA848cc3E160417d05261FE5693F41));
  IMetadataRegistry metadataRegistry = IMetadataRegistry(address(0xD2168C6c33fEe907FB12024E5e7e9219083fBb19));

  function run(string memory fileName_) public virtual {
    string memory json_ = readInput(fileName_);
    address deployedTrigger_ = deployTrigger(json_);
    assert(
      deployedTrigger_
        == ownableTriggerFactory.computeTriggerAddress(
          caller_, router.computeSalt(caller_, json_.readBytes32(".triggerSalt"))
        )
    );
    address deployedSafetyModule_ = deploySafetyModule(json_, deployedTrigger_);
    assert(
      deployedSafetyModule_
        == cozySafetyModuleManager.computeSafetyModuleAddress(
          address(router), router.computeSalt(caller_, json_.readBytes32(".safetyModuleSalt"))
        )
    );
    updateMetadata(json_, deployedSafetyModule_);
  }

  function deployTrigger(string memory json_) public virtual returns (address) {
    // -------- Load json --------
    address triggerOwner_ = json_.readAddress(".triggerOwner");
    bytes32 triggerSalt_ = json_.readBytes32(".triggerSalt");
    TriggerMetadata memory triggerMetadata_ = TriggerMetadata(
      json_.readString(".triggerName"),
      json_.readString(".triggerDescription"),
      json_.readString(".triggerLogoURI"),
      json_.readString(".triggerExtraData")
    );

    // -------------------------------------
    // ----------- Generate Calldata -------
    // -------------------------------------
    address targetContract_ = address(router);
    uint256 value_ = 0;
    bytes memory callData_ = abi.encodeWithSelector(
      router.deployOwnableTrigger.selector,
      triggerOwner_,
      TriggerMetadata(
        triggerMetadata_.description, triggerMetadata_.extraData, triggerMetadata_.logoURI, triggerMetadata_.name
      ),
      triggerSalt_
    );

    console2.log("targetContract", targetContract_);
    console2.log("value", value_);
    console2.log("calldata:");
    console2.logBytes(callData_);

    // -------------------------------------
    // ----------- Deploy Trigger ----------
    // -------------------------------------
    console2.log("========");
    console2.log("Deploying OwnableTrigger...");
    console2.log("    triggerOwner", triggerOwner_);
    console2.log("    triggerName", triggerMetadata_.name);
    console2.log("    triggerDescription", triggerMetadata_.description);
    console2.log("    triggerLogoURI", triggerMetadata_.logoURI);
    console2.log("    triggerExtraData", triggerMetadata_.extraData);

    require(triggerOwner_ != address(0), "Trigger owner cannot be zero address");

    vm.broadcast();
    ITrigger deployedTrigger_ = router.deployOwnableTrigger(
      triggerOwner_,
      TriggerMetadata(
        triggerMetadata_.description, triggerMetadata_.extraData, triggerMetadata_.logoURI, triggerMetadata_.name
      ),
      triggerSalt_
    );

    console2.log("OwnableTrigger deployed", address(deployedTrigger_));
    console2.log("========");

    return address(deployedTrigger_);
  }

  function deploySafetyModule(string memory json_, address deployedTrigger_) public virtual returns (address) {
    // -------- Load json --------
    address safetyModuleOwner_ = json_.readAddress(".safetyModuleOwner");
    address safetyModulePauser_ = json_.readAddress(".safetyModulePauser");
    bytes32 safetyModuleSalt_ = json_.readBytes32(".safetyModuleSalt");

    address reservePoolAsset_ = json_.readAddress(".reservePoolAsset");
    uint256 reservePoolMaxSlashPercentage_ = json_.readUint(".reservePoolMaxSlashPercentage");
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig(reservePoolMaxSlashPercentage_, IERC20(reservePoolAsset_));

    address payoutHandler_ = json_.readAddress(".payoutHandlerAddress");
    TriggerConfig[] memory triggerConfigs_ = new TriggerConfig[](1);
    triggerConfigs_[0] = TriggerConfig(ITrigger(deployedTrigger_), payoutHandler_, true);

    Delays memory delays_ = Delays(
      uint64(json_.readUint(".delaysConfigUpdateDelay")),
      uint64(json_.readUint(".delaysConfigUpdateGracePeriod")),
      uint64(json_.readUint(".delaysWithdrawalDelay"))
    );

    UpdateConfigsCalldataParams memory configs_ =
      UpdateConfigsCalldataParams(reservePoolConfigs_, triggerConfigs_, delays_);

    // -------------------------------------
    // ----------- Generate Calldata -------
    // -------------------------------------
    address targetContract_ = address(router);
    uint256 value_ = 0;
    bytes memory callData_ = abi.encodeWithSelector(
      router.deploySafetyModule.selector, safetyModuleOwner_, safetyModulePauser_, configs_, safetyModuleSalt_
    );

    console2.log("targetContract", targetContract_);
    console2.log("value", value_);
    console2.log("calldata:");
    console2.logBytes(callData_);

    // -------------------------------------
    // ------ Deploy SafetyModule ----------
    // -------------------------------------
    console2.log("========");
    console2.log("Deploying SafetyModule...");
    console2.log("    safetyModuleOwner", safetyModuleOwner_);
    console2.log("    safetyModulePauser", safetyModulePauser_);
    console2.log("    reservePoolAsset", reservePoolAsset_);
    console2.log("    reservePoolMaxSlashPercentage", reservePoolMaxSlashPercentage_);
    console2.log("    triggerPayoutHandler", payoutHandler_);
    console2.log("    triggerAddress", deployedTrigger_);
    console2.log("    delaysConfigUpdateDelay", delays_.configUpdateDelay);
    console2.log("    delaysConfigUpdateGracePeriod", delays_.configUpdateGracePeriod);
    console2.log("    delaysWithdrawDelay", delays_.withdrawDelay);

    vm.broadcast();
    ISafetyModule safetyModule =
      router.deploySafetyModule(safetyModuleOwner_, safetyModulePauser_, configs_, safetyModuleSalt_);

    console2.log("SafetyModule deployed", address(safetyModule));
    console2.log("========");

    return address(safetyModule);
  }

  function updateMetadata(string memory json_, address deployedSafetyModule_) public virtual {
    // -------- Load json --------
    IMetadataRegistry.Metadata memory metadata_ = IMetadataRegistry.Metadata(
      json_.readString(".name"),
      json_.readString(".description"),
      json_.readString(".logoURI"),
      json_.readString(".extraData")
    );

    // -------------------------------------
    // ----------- Generate Calldata -------
    // -------------------------------------
    address targetContract_ = address(router);
    uint256 value_ = 0;
    bytes memory callData_ = abi.encodeWithSelector(
      router.updateSafetyModuleMetadata.selector, metadataRegistry, deployedSafetyModule_, metadata_
    );

    console2.log("targetContract", targetContract_);
    console2.log("value", value_);
    console2.log("calldata:");
    console2.logBytes(callData_);

    // -------------------------------------
    // ------ Deploy SafetyModule ----------
    // -------------------------------------
    console2.log("========");
    console2.log("Updating SafetyModule Metadata...");
    console2.log("    SafetyModule", deployedSafetyModule_);
    console2.log("    Metadata.name", metadata_.name);
    console2.log("    Metadata.description", metadata_.description);
    console2.log("    Metadata.logoURI", metadata_.logoURI);
    console2.log("    Metadata.extraData", metadata_.extraData);

    vm.broadcast();
    router.updateSafetyModuleMetadata(metadataRegistry, deployedSafetyModule_, metadata_);

    console2.log("SafetyModule Metadata updated");
    console2.log("========");
  }
}
