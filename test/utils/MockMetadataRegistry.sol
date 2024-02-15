// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IMetadataRegistry} from "../../src/interfaces/IMetadataRegistry.sol";
import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";

contract MockMetadataRegistry is IMetadataRegistry {
  address public cozyRouter;

  constructor(address cozyRouter_) {
    cozyRouter = cozyRouter_;
  }

  function updateSafetyModuleMetadata(address safetyModule_, Metadata calldata, /* metadata_ */ address caller_)
    public
    view
  {
    require(msg.sender == cozyRouter, "MockMetadataRegistry: msg.sender is not the CozyRouter");
    require(
      caller_ == ISafetyModule(safetyModule_).owner(),
      "MockMetadataRegistry: caller_ is not the owner of the safety module"
    );
  }
}
