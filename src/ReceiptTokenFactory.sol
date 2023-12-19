// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {IReceiptToken} from "./interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "./interfaces/IReceiptTokenFactory.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";

/**
 * @notice Deploys new ReceiptTokens.
 * @dev ReceiptTokens are compliant with ERC-20 and ERC-2612.
 */
contract ReceiptTokenFactory is IReceiptTokenFactory {
  using Clones for address;

  /// @notice Address of the ReceiptToken logic contract used to deploy new ReceiptToken.
  IReceiptToken public immutable receiptTokenLogic;

  /// @dev Thrown if an address parameter is invalid.
  error InvalidAddress();

  /// @param receiptTokenLogic_ Logic contract for deploying new ReceiptTokens.
  constructor(IReceiptToken receiptTokenLogic_) {
    _assertAddressNotZero(address(receiptTokenLogic_));
    receiptTokenLogic = receiptTokenLogic_;
  }

  /// @notice Creates a new ReceiptToken contract with the given number of `decimals_`. The ReceiptToken's safety module
  /// is identified by the caller address. The pool id of the ReceiptToken in the safety module and its `PoolType` is
  /// used to generate a unique salt for deploy.
  function deployReceiptToken(uint8 poolId_, PoolType poolType_, uint8 decimals_)
    external
    returns (IReceiptToken receiptToken_)
  {
    // The caller is the safety module.
    ISafetyModule safetyModule_ = ISafetyModule(msg.sender);

    // We generate the salt from the safety module-pool id-pool type, which must be unique, and concatenate it with the
    // chain ID to prevent the same ReceiptToken address existing on multiple chains for different safety modules or
    // pools.
    receiptToken_ =
      IReceiptToken(address(receiptTokenLogic).cloneDeterministic(salt(safetyModule_, poolId_, poolType_)));
    receiptToken_.initialize(safetyModule_, decimals_);
    emit ReceiptTokenDeployed(receiptToken_, safetyModule_, poolId_, poolType_, decimals_);
  }

  /// @notice Given a `safetyModule_`, its `poolId_`, and `poolType_`, compute and return the address of its
  /// ReceiptToken.
  function computeAddress(ISafetyModule safetyModule_, uint8 poolId_, PoolType poolType_)
    external
    view
    returns (address)
  {
    return Clones.predictDeterministicAddress(
      address(receiptTokenLogic), salt(safetyModule_, poolId_, poolType_), address(this)
    );
  }

  /// @notice Given a `safetyModule_`, its `poolId_`, and `poolType_`, return the salt used to compute the ReceiptToken
  /// address.
  function salt(ISafetyModule safetyModule_, uint8 poolId_, PoolType poolType_) public view returns (bytes32) {
    return keccak256(abi.encode(safetyModule_, poolId_, poolType_, block.chainid));
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
