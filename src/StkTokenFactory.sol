// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {IStkToken} from "./interfaces/IStkToken.sol";
import {IStkTokenFactory} from "./interfaces/IStkTokenFactory.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";

/**
 * @notice Deploys new StkTokens.
 * @dev StkTokens are compliant with ERC-20 and ERC-2612.
 */
contract StkTokenFactory is IStkTokenFactory {
  using Clones for address;

  /// @notice Address of the StkToken logic contract used to deploy new StkTokens.
  IStkToken public immutable stkTokenLogic;

  /// @dev Thrown if an address parameter is invalid.
  error InvalidAddress();

  /// @param stkTokenLogic_ Logic contract for deploying new StkTokens.
  constructor(IStkToken stkTokenLogic_) {
    _assertAddressNotZero(address(stkTokenLogic_));
    stkTokenLogic = stkTokenLogic_;
  }

  /// @notice Creates a new StkToken contract with the given number of `decimals_`. The StkToken's safety module is
  /// identified by the caller address. The reserve pool id of the StkToken in the safety module is used to generate
  /// a unique salt for deploy.
  function deployStkToken(uint8 reservePoolId_, uint8 decimals_) external returns (IStkToken stkToken_) {
    // The caller is the safety module.
    ISafetyModule safetyModule_ = ISafetyModule(msg.sender);

    // We generate the salt from the safety module-reserve pool id, which must be unique, and concatenate it with the
    // chain ID to prevent the same StkToken address existing on multiple chains for different safety modules or pools.
    stkToken_ = IStkToken(address(stkTokenLogic).cloneDeterministic(salt(safetyModule_, reservePoolId_)));
    stkToken_.initialize(safetyModule_, decimals_);
    emit StkTokenDeployed(stkToken_, safetyModule_, reservePoolId_, decimals_);
  }

  /// @notice Given a `safetyModule_` and its `reservePoolId_`, compute and return the address of its StkToken.
  function computeAddress(ISafetyModule safetyModule_, uint8 reservePoolId_) external view returns (address) {
    return
      Clones.predictDeterministicAddress(address(stkTokenLogic), salt(safetyModule_, reservePoolId_), address(this));
  }

  /// @notice Given the `safetyModule_` and `reservePoolId_`, return the salt used to compute the StkToken address.
  function salt(ISafetyModule safetyModule_, uint8 reservePoolId_) public view returns (bytes32) {
    return keccak256(abi.encode(safetyModule_, reservePoolId_, block.chainid));
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
