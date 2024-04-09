// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {ReservePoolConfig, UpdateConfigsCalldataParams} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {TriggerConfig, TriggerMetadata} from "../src/lib/structs/Trigger.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";

/**
 * @dev To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $ETH_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/DeployUnionSafetyModule.s.sol \
 *   --sig "run(string)" "deploy-union-safety-module-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions.
 * forge script script/DeployUnionSafetyModule.s.sol \
 *   --sig "run(string)" "deploy-union-safety-module-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract DeployUnionSafetyModule is ScriptUtils {
  using stdJson for string;

  CozyRouter router = CozyRouter(payable(address(0x707C39F1AaA7c8051287b3b231BccAa8CD72138f)));

  function run(string memory fileName_) public virtual {
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

    address payoutHandler_ = json_.readAddress(".payoutHandlerAddress");
    address trigger_ = json_.readAddress(".triggerAddress");
    TriggerConfig[] memory triggerConfigs_ = new TriggerConfig[](1);
    triggerConfigs_[0] = TriggerConfig(ITrigger(trigger_), payoutHandler_, true);

    Delays memory delays_ = Delays(
      uint64(json_.readUint(".delaysConfigUpdateDelay")),
      uint64(json_.readUint(".delaysConfigUpdateGracePeriod")),
      uint64(json_.readUint(".delaysWithdrawalDelay"))
    );

    UpdateConfigsCalldataParams memory configs_ =
      UpdateConfigsCalldataParams(reservePoolConfigs_, triggerConfigs_, delays_);

    console2.log("========");
    console2.log("Deploying SafetyModule...");
    console2.log("    safetyModuleOwner", safetyModuleOwner_);
    console2.log("    safetyModulePauser", safetyModulePauser_);
    console2.log("    reservePoolAsset", reservePoolAsset_);
    console2.log("    reservePoolMaxSlashPercentage", reservePoolMaxSlashPercentage_);
    console2.log("    triggerPayoutHandler", payoutHandler_);
    console2.log("    triggerAddress", trigger_);
    console2.log("    delaysConfigUpdateDelay", delays_.configUpdateDelay);
    console2.log("    delaysConfigUpdateGracePeriod", delays_.configUpdateGracePeriod);
    console2.log("    delaysWithdrawDelay", delays_.withdrawDelay);

    vm.broadcast();
    ISafetyModule safetyModule =
      router.deploySafetyModule(safetyModuleOwner_, safetyModulePauser_, configs_, safetyModuleSalt_);

    console2.log("SafetyModule deployed", address(safetyModule));
    console2.log("========");
  }
}
