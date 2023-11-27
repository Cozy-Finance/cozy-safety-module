// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SafetyModule} from "../../src/cozy-v2/SafetyModule.sol";
import {ScriptUtils} from "../utils/ScriptUtils.sol";

/**
 * @dev This script deploys a Cozy V2 SafetyModule.
 * Before executing, the input json file `script/input/<chain-id>/deploy-cozy-v2-safety-module.json` should be reviewed.
 *
 * To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $OPTIMISM_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/cozy-v2/DeployCozyV2SafetyModule.s.sol \
 *   --sig "run(string)" "deploy-cozy-v2-safety-module"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions.
 * forge script script/cozy-v2/DeployCozyV2SafetyModule.s.sol \
 *   --sig "run(string)" "deploy-cozy-v2-safety-module"
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract DeployCozyV2SafetyModule is ScriptUtils {
  using stdJson for string;

  function run(string memory fileName) public {
    // -------- Load json --------

    string memory json_ = readInput(fileName);
    address owner_ = json_.readAddress(".owner");
    address trigger_ = json_.readAddress(".trigger");

    // -------- Deploy and initialize --------

    // Deploy safety module
    vm.broadcast();
    SafetyModule safetyModule_ = new SafetyModule();

    // Initialize deployed safety module
    vm.broadcast();
    safetyModule_.initialize(owner_, trigger_);

    // Log deployment
    console2.log("Safety Module deployed:", address(safetyModule_));
    console2.log("    owner:", safetyModule_.owner());
    console2.log("    trigger:", safetyModule_.trigger());
  }
}
