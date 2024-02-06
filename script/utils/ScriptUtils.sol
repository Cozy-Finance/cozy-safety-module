// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ScriptUtils is Script {
  using stdJson for string;

  string INPUT_FOLDER = "/script/input/";

  // Returns the json string for the specified filename from `INPUT_FOLDER`.
  function readInput(string memory _fileName) internal view returns (string memory) {
    string memory _root = vm.projectRoot();
    string memory _chainInputFolder = string.concat(INPUT_FOLDER, vm.toString(block.chainid), "/");
    string memory _inputFile = string.concat(_fileName, ".json");
    string memory _inputPath = string.concat(_root, _chainInputFolder, _inputFile);
    return vm.readFile(_inputPath);
  }

  // Use this to assert validity of a provided token contract.
  function assertToken(IERC20 token, string memory name, uint256 decimals) internal view {
    require(stringCompare(token.name(), name), string.concat("Provided ", name, " contract has an incorrect name."));
    require(
      token.decimals() == decimals, string.concat("Provided ", name, " contract has an incorrect amount of decimals.")
    );

    // Also loosely validate the token's interface by ensuring a totalSupply call don't revert.
    token.totalSupply();
  }

  function stringCompare(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
  }
}
