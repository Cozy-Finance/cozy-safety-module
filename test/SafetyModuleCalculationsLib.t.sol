// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleCalculationsLib} from "../src/lib/SafetyModuleCalculationsLib.sol";
import {TestBase} from "./utils/TestBase.sol";

contract SafetyModuleCalculationsLibTest is TestBase {
  function test_concrete_convertToReceiptTokenAmount() public {
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 1000), 100);
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 2000), 50);
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 4000), 25);
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 8000), 12); // Rounds down
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 16_000), 6);
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 32_000), 3);
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 64_000), 1); // Rounds down
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 128_000), 0); // Rounds down

    // Check that `poolAmount_` is floored properly.
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(100, 1000, 0), 100 * 1000);
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(5, 30, 0), 5 * 30);
  }

  function testFuzz_floor_convertToReceiptTokenAmount(uint64 assetAmount_, uint64 tokenSupply_) public {
    assertEq(
      SafetyModuleCalculationsLib.convertToReceiptTokenAmount(assetAmount_, tokenSupply_, 0),
      SafetyModuleCalculationsLib.convertToReceiptTokenAmount(assetAmount_, tokenSupply_, 1)
    );
  }

  function testFuzz_zeroTokenSupply_convertToReceiptTokenAmount(uint256 assetAmount_, uint256 poolAmount_) public {
    assertEq(SafetyModuleCalculationsLib.convertToReceiptTokenAmount(assetAmount_, 0, poolAmount_), assetAmount_);
  }

  function test_concrete_convertToAssetAmount() public {
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 1000), 100);
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 500), 50);
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 250), 25);
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 125), 12); // Rounds down
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 62), 6); // Rounds down
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 31), 3); // Rounds down
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 15), 1); // Rounds down

    // Check that `poolAmount_` is floored properly.
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 1000, 0), 0);
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(5, 30, 0), 0);
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(100, 10, 0), 10);
  }

  function testFuzz_floor_convertToAssetAmount(uint128 receiptTokenAmount_, uint128 receiptTokenSupply_) public {
    assertEq(
      SafetyModuleCalculationsLib.convertToAssetAmount(receiptTokenAmount_, receiptTokenSupply_, 0),
      SafetyModuleCalculationsLib.convertToAssetAmount(receiptTokenAmount_, receiptTokenSupply_, 1)
    );
  }

  function testFuzz_zeroTokenSupply_convertToAssetAmount(uint256 receiptTokenAmount_, uint256 poolAmount_) public {
    assertEq(SafetyModuleCalculationsLib.convertToAssetAmount(receiptTokenAmount_, 0, poolAmount_), 0);
  }

  function testFuzz_convertBackAndForthAssetAmount(
    uint128 assetAmount_,
    uint128 receiptTokenSupply_,
    uint128 poolAmount_
  ) public {
    uint256 receiptTokenAmount_ =
      SafetyModuleCalculationsLib.convertToReceiptTokenAmount(assetAmount_, receiptTokenSupply_, poolAmount_);
    uint256 finalAssetAmount_ =
      SafetyModuleCalculationsLib.convertToAssetAmount(receiptTokenAmount_, receiptTokenSupply_, poolAmount_);
    assertLe(finalAssetAmount_, assetAmount_);
  }

  function testFuzz_convertBackAndForthReceiptTokenAmount(
    uint128 receiptTokenAmount_,
    uint128 receiptTokenSupply_,
    uint128 poolAmount_
  ) public {
    uint256 assetAmount_ =
      SafetyModuleCalculationsLib.convertToAssetAmount(receiptTokenAmount_, receiptTokenSupply_, poolAmount_);
    uint256 finalReceiptTokenAmount_ =
      SafetyModuleCalculationsLib.convertToReceiptTokenAmount(assetAmount_, receiptTokenSupply_, poolAmount_);
    assertLe(finalReceiptTokenAmount_, receiptTokenAmount_);
  }
}
