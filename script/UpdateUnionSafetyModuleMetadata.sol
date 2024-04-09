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
import {IMetadataRegistry} from "../src/interfaces/IMetadataRegistry.sol";

/**
 * @dev To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $ETH_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/UpdateUnionSafetyModuleMetadata.s.sol \
 *   --sig "run(string)" "update-union-safety-module-metadata-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions.
 * forge script script/UpdateUnionSafetyModuleMetadata.s.sol \
 *   --sig "run(string)" "update-union-safety-module-metadata-<test or production>"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract UpdateUnionSafetyModuleMetadata is ScriptUtils {
  using stdJson for string;

  CozyRouter router = CozyRouter(payable(address(0x707C39F1AaA7c8051287b3b231BccAa8CD72138f)));
  IMetadataRegistry metadataRegistry = IMetadataRegistry(address(0xD2168C6c33fEe907FB12024E5e7e9219083fBb19));

  function run(string memory fileName_) public virtual {
    // -------- Load json --------
    string memory json_ = readInput(fileName_);

    // -------------------------------------
    // ------ Deploy SafetyModule ----------
    // -------------------------------------
    address safetyModule_ = json_.readAddress(".safetyModuleAddress");
    IMetadataRegistry.Metadata memory metadata_ = IMetadataRegistry.Metadata(
      json_.readString(".name"),
      json_.readString(".description"),
      json_.readString(".logoURI"),
      json_.readString(".extraData")
    );

    console2.log("========");
    console2.log("Updating SafetyModule Metadata...");
    console2.log("    SafetyModule", safetyModule_);
    console2.log("    Metadata.name", metadata_.name);
    console2.log("    Metadata.description", metadata_.description);
    console2.log("    Metadata.logoURI", metadata_.logoURI);
    console2.log("    Metadata.extraData", metadata_.extraData);

    vm.broadcast();
    router.updateSafetyModuleMetadata(metadataRegistry, safetyModule_, metadata_);

    console2.log("SafetyModule Metadata updated");
    console2.log("========");
  }
}
