// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {ScriptUtils} from "./utils/ScriptUtils.sol";

/**
 * @notice Purpose: Local deploy, testing, and production.
 *
 * This script deploys a TimelockController.
 *
 * To run this script:
 *
 * ```sh
 * # Start anvil, forking from the current state of the desired chain.
 * anvil --fork-url $OPTIMISM_RPC_URL
 *
 * # In a separate terminal, perform a dry run the script.
 * forge script script/DeployTimelockController.s.sol \
 *   --sig "run(string)" "deploy-timelock-<test or production>" \
 *   --rpc-url "http://127.0.0.1:8545" \
 *   -vvvv
 *
 * # Or, to broadcast transactions with etherscan verification.
 * forge script script/DeployTimelockController.s.sol \
 *   --sig "run(string)" "deploy-timelock-<test or production>" \
 *   --rpc-url "http://127.0.0.1:8545" \
 *   --private-key $OWNER_PRIVATE_KEY \
 *   --etherscan-api-key $ETHERSCAN_KEY \
 *   --verify \
 *   --broadcast \
 *   -vvvv
 * ```
 */
contract DeployTimelockController is ScriptUtils {
  using stdJson for string;

  // ---------------------------
  // -------- Execution --------
  // ---------------------------

  function run(string memory _fileName) public {
    string memory _json = readInput(_fileName);
    uint256 minDelay_ = _json.readUint(".minDelay");

    address[] memory proposers_ = new address[](1);
    address[] memory executors_ = new address[](1);
    proposers_[0] = _json.readAddress(".proposer");
    executors_[0] = _json.readAddress(".executor");

    require(proposers_[0] != address(0), "proposer should not be the zero address");
    require(executors_[0] != address(0), "executor should not be the zero address");

    console2.log("Deploying TimelockController...");
    console2.log("    proposer", proposers_[0]);
    console2.log("    executor", executors_[0]);
    vm.broadcast();
    // We don't need the optional admin role which can be used for initial configuration of the timelock without delay,
    // so we pass the zero address for it.
    TimelockController timelockController_ = new TimelockController(minDelay_, proposers_, executors_, address(0));
    console2.log("TimelockController deployed", address(timelockController_));
  }
}
