// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../../src/interfaces/IERC20.sol";

contract MockUMAOracle {
  function requestPrice(
    bytes32, /* identifier */
    uint256, /* timestamp */
    bytes memory, /* ancillaryData */
    IERC20, /* currency */
    uint256 /* reward */
  ) external virtual returns (uint256 totalBond) {
    return 0;
  }

  function setEventBased(bytes32, /* identifier */ uint256, /* timestamp */ bytes memory /* ancillaryData */ )
    external
    virtual
  {
    // Do nothing.
  }

  function setBond(
    bytes32, /* identifier */
    uint256, /* timestamp */
    bytes memory, /* ancillaryData */
    uint256 /* bond */
  ) external virtual returns (uint256 totalBond) {
    return 0;
  }

  function setCustomLiveness(
    bytes32, /* identifier */
    uint256, /* timestamp */
    bytes memory, /* ancillaryData */
    uint256 /* customLiveness */
  ) external virtual {
    // Do nothing.
  }

  function setCallbacks(
    bytes32, /* identifier */
    uint256, /* timestamp */
    bytes memory, /* ancillaryData */
    bool, /* callbackOnPriceProposed */
    bool, /* callbackOnPriceDisputed */
    bool /* callbackOnPriceSettled */
  ) external virtual {
    // Do nothing.
  }
}
