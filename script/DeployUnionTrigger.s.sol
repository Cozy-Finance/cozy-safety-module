// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {TriggerConfig, TriggerMetadata} from "../src/lib/structs/Trigger.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";

/**
 * @dev To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $ETH_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/DeployUnionTrigger.s.sol \
 *   --sig "run(string)" "deploy-union-trigger-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions.
 * forge script script/DeployUnionTrigger.s.sol \
 *   --sig "run(string)" "deploy-union-trigger-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract DeployUnionTrigger is ScriptUtils {
  using stdJson for string;

  CozyRouter router = CozyRouter(payable(address(0x707C39F1AaA7c8051287b3b231BccAa8CD72138f)));

  function run(string memory fileName_) public virtual {
    // -------- Load json --------
    string memory json_ = readInput(fileName_);

    // -------------------------------------
    // ----------- Deploy Trigger ----------
    // -------------------------------------
    address triggerOwner_ = json_.readAddress(".triggerOwner");
    bytes32 triggerSalt_ = json_.readBytes32(".triggerSalt");
    TriggerMetadata memory triggerMetadata_ = TriggerMetadata(
      json_.readString(".triggerName"),
      json_.readString(".triggerDescription"),
      json_.readString(".triggerLogoURI"),
      json_.readString(".triggerExtraData")
    );

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
  }
}
