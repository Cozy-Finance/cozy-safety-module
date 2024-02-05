// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IDripModel} from "../../src/interfaces/IDripModel.sol";
import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";
import {Delays} from "../../src/lib/structs/Delays.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {Test} from "forge-std/Test.sol";
import {TestAssertions} from "./TestAssertions.sol";

contract TestBase is Test, TestAssertions {
  uint256 internal constant PANIC_ASSERT = 0x01;
  uint256 internal constant PANIC_MATH_UNDEROVERFLOW = 0x11;
  uint256 internal constant PANIC_MATH_DIVIDE_BY_ZERO = 0x12;
  uint256 internal constant PANIC_ARRAY_OUT_OF_BOUNDS = 0x32;
  uint256 internal constant INDEX_OUT_OF_BOUNDS = 0x32;

  bytes4 internal constant PANIC_SELECTOR = bytes4(keccak256("Panic(uint256)"));

  function _expectEmit() internal {
    vm.expectEmit(true, true, true, true);
  }

  function _randomAddress() internal view returns (address payable) {
    return payable(address(uint160(_randomUint256())));
  }

  function _randomBytes32() internal view returns (bytes32) {
    return keccak256(
      abi.encode(block.timestamp, blockhash(0), gasleft(), tx.origin, keccak256(msg.data), address(this).codehash)
    );
  }

  function _randomUint8() internal view returns (uint8) {
    return uint8(_randomUint256());
  }

  function _randomUint16() internal view returns (uint16) {
    return uint16(_randomUint256());
  }

  function _randomUint32() internal view returns (uint32) {
    return uint32(_randomUint256());
  }

  function _randomUint64() internal view returns (uint64) {
    return uint64(_randomUint256());
  }

  function _randomUint120() internal view returns (uint120) {
    return uint120(_randomUint256());
  }

  function _randomUint128() internal view returns (uint128) {
    return uint128(_randomUint256());
  }

  function _randomUint256() internal view returns (uint256) {
    return uint256(_randomBytes32());
  }

  function _randomUint256(uint256 modulo_) internal view returns (uint256) {
    return uint256(_randomBytes32()) % modulo_;
  }

  function _randomIndices(uint256 count_) internal view returns (uint256[] memory idxs_) {
    idxs_ = new uint256[](count_);
    for (uint256 i; i < count_; ++i) {
      idxs_[i] = i;
    }
    for (uint256 i; i < count_; ++i) {
      if (idxs_[i] == i) {
        uint256 r = i + _randomUint256(count_ - i);
        (idxs_[i], idxs_[r]) = (idxs_[r], idxs_[i]);
      }
    }
  }

  /// @dev Returns a random uint256 in range [min_, max_]. min_ must be greater than max_.
  function _randomUint256InRange(uint256 min_, uint256 max_) internal view returns (uint256) {
    uint256 base_ = _randomUint256();
    return bound(base_, min_, max_);
  }

  function _expectPanic(uint256 code_) internal {
    vm.expectRevert(abi.encodeWithSelector(PANIC_SELECTOR, code_));
  }

  function getDelays(ISafetyModule safetyModule_) internal view returns (Delays memory) {
    (uint64 configUpdateDelay, uint64 configUpdateGracePeriod, uint64 withdrawDelay) = safetyModule_.delays();
    return Delays({
      configUpdateDelay: configUpdateDelay,
      configUpdateGracePeriod: configUpdateGracePeriod,
      withdrawDelay: withdrawDelay
    });
  }

  function getReservePool(ISafetyModule safetyModule_, uint256 reservePoolId_)
    internal
    view
    returns (ReservePool memory)
  {
    return safetyModule_.reservePools(reservePoolId_);
  }

  function copyReservePool(ReservePool memory original_) internal pure returns (ReservePool memory copied_) {
    copied_.asset = original_.asset;
    copied_.depositReceiptToken = original_.depositReceiptToken;
    copied_.depositAmount = original_.depositAmount;
    copied_.pendingWithdrawalsAmount = original_.pendingWithdrawalsAmount;
    copied_.feeAmount = original_.feeAmount;
    copied_.maxSlashPercentage = original_.maxSlashPercentage;
    copied_.lastFeesDripTime = original_.lastFeesDripTime;
  }
}
