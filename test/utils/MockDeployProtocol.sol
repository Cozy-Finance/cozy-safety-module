// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "../../src/interfaces/ISafetyModuleFactory.sol";
import {IManager} from "../../src/interfaces/IManager.sol";
import {IReceiptToken} from "../../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../../src/interfaces/IReceiptTokenFactory.sol";
import {IDripModel} from "../../src/interfaces/IDripModel.sol";
import {Manager} from "../../src/Manager.sol";
import {SafetyModule} from "../../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../../src/SafetyModuleFactory.sol";
import {ReceiptToken} from "../../src/ReceiptToken.sol";
import {StkToken} from "../../src/StkToken.sol";
import {ReceiptTokenFactory} from "../../src/ReceiptTokenFactory.sol";
import {MockDripModel} from "./MockDripModel.sol";
import {TestBase} from "../utils/TestBase.sol";

contract MockDeployer is TestBase {
  Manager manager;
  SafetyModuleFactory safetyModuleFactory;
  ReceiptToken depositTokenLogic;
  StkToken stkTokenLogic;
  ReceiptTokenFactory receiptTokenFactory;
  MockDripModel feeDripModel;
  ISafetyModule safetyModuleLogic;

  address owner = address(this);
  address pauser = address(0xBEEF);

  uint256 constant DEFAULT_FEE_DRIP_MODEL_CONSTANT = 0.5e18;

  function deployMockProtocol() public virtual {
    uint256 nonce_ = vm.getNonce(address(this));
    IDripModel computedAddrFeeDripModel_ = IDripModel(vm.computeCreateAddress(address(this), nonce_));
    IManager computedAddrManager_ = IManager(vm.computeCreateAddress(address(this), nonce_ + 1));
    ISafetyModule computedAddrSafetyModuleLogic_ = ISafetyModule(vm.computeCreateAddress(address(this), nonce_ + 2));
    ISafetyModuleFactory computedAddrSafetyModuleFactory_ =
      ISafetyModuleFactory(vm.computeCreateAddress(address(this), nonce_ + 3));
    IReceiptToken depositTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 4));
    IReceiptToken stkTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 5));
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(address(this), nonce_ + 6));

    feeDripModel = new MockDripModel(DEFAULT_FEE_DRIP_MODEL_CONSTANT);
    manager = new Manager(owner, pauser, computedAddrSafetyModuleFactory_, computedAddrFeeDripModel_);

    safetyModuleLogic = ISafetyModule(address(new SafetyModule(computedAddrManager_, computedAddrReceiptTokenFactory_)));
    safetyModuleFactory = new SafetyModuleFactory(computedAddrManager_, computedAddrSafetyModuleLogic_);

    depositTokenLogic = new ReceiptToken(computedAddrManager_);
    stkTokenLogic = new StkToken(computedAddrManager_);
    receiptTokenFactory = new ReceiptTokenFactory(depositTokenLogic_, stkTokenLogic_);
  }
}

contract MockDeployProtocol is MockDeployer {
  function setUp() public virtual {
    deployMockProtocol();
  }
}
