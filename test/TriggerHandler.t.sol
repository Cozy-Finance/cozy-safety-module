// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../src/interfaces/IERC20.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {ITriggerHandlerErrors} from "../src/interfaces/ITriggerHandlerErrors.sol";
import {TriggerHandler} from "../src/lib/TriggerHandler.sol";
import {UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {SafetyModuleState, TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {PayoutHandler} from "../src/lib/structs/PayoutHandler.sol";
import {Trigger} from "../src/lib/structs/Trigger.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

contract TriggerHandlerTest is TestBase {
  TestableTriggerHandler component;
  ITrigger mockTrigger;
  address mockPayoutHandler;

  function setUp() public {
    component = new TestableTriggerHandler();
    mockTrigger = ITrigger(address(new MockTrigger(TriggerState.TRIGGERED)));

    mockPayoutHandler = _randomAddress();
    Trigger memory triggerData_ = Trigger({exists: true, payoutHandler: mockPayoutHandler, triggered: false});
    component.mockSetTriggerData(mockTrigger, triggerData_);
  }

  function test_trigger() public {
    _expectEmit();
    emit TestableTriggerHandler.TestRewardsDripped();
    _expectEmit();
    emit TestableTriggerHandler.TestFeesDripped();
    _expectEmit();
    emit TriggerHandler.Triggered(mockTrigger);
    component.trigger(mockTrigger);

    assertEq(component.safetyModuleState(), SafetyModuleState.TRIGGERED);
    assertEq(component.numPendingSlashes(), 1);
    assertEq(component.getPayoutHandlerData(mockPayoutHandler).numPendingSlashes, 1);
    assertEq(component.getTriggerData(mockTrigger).triggered, true);
  }

  function testFuzz_trigger_invalidTrigger(ITrigger trigger_) public {
    vm.assume(address(trigger_) != address(mockTrigger));
    vm.expectRevert(ITriggerHandlerErrors.InvalidTrigger.selector);
    component.trigger(trigger_);
  }

  function test_trigger_invalidTriggerState() public {
    MockTrigger(address(mockTrigger)).mockState(TriggerState.ACTIVE);
    vm.expectRevert(ITriggerHandlerErrors.InvalidTrigger.selector);
    component.trigger(mockTrigger);
  }

  function test_trigger_triggerAlreadyTriggered() public {
    Trigger memory triggerData_ = Trigger({exists: true, payoutHandler: mockPayoutHandler, triggered: true});
    component.mockSetTriggerData(mockTrigger, triggerData_);
    vm.expectRevert(ITriggerHandlerErrors.InvalidTrigger.selector);
    component.trigger(mockTrigger);
  }

  // TODO: Uncomment once StateChanger is implemented.
  // function testFail_trigger_safetyModuleNotActive() public {
  //   component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);

  //   // Expect this test to fail because this event isn't emitted in this case.
  //   _expectEmit();
  //   emit StateChanger.SafetyModuleStateUpdated(SafetyModuleState.TRIGGERED);
  //   component.trigger(mockTrigger);
  // }

  function test_trigger_multipleTriggers() public {
    ITrigger mockTriggerB_ = ITrigger(address(new MockTrigger(TriggerState.TRIGGERED)));
    Trigger memory triggerData_ = Trigger({exists: true, payoutHandler: mockPayoutHandler, triggered: false});
    component.mockSetTriggerData(mockTriggerB_, triggerData_);

    // Trigger the safety module using the trigger from setUp.
    component.trigger(mockTrigger);
    assertEq(component.safetyModuleState(), SafetyModuleState.TRIGGERED);
    assertEq(component.numPendingSlashes(), 1);
    assertEq(component.getPayoutHandlerData(mockPayoutHandler).numPendingSlashes, 1);
    assertEq(component.getTriggerData(mockTrigger).triggered, true);

    // Call trigger again using the trigger setup in this test.
    component.trigger(mockTriggerB_);
    assertEq(component.safetyModuleState(), SafetyModuleState.TRIGGERED);
    assertEq(component.numPendingSlashes(), 2);
    assertEq(component.getPayoutHandlerData(mockPayoutHandler).numPendingSlashes, 2);
    assertEq(component.getTriggerData(mockTrigger).triggered, true);
  }
}

contract TestableTriggerHandler is TriggerHandler {
  event TestRewardsDripped();
  event TestFeesDripped();

  // -------- Getters --------

  function getPayoutHandlerData(address payoutHandler_) external view returns (PayoutHandler memory) {
    return payoutHandlerData[payoutHandler_];
  }

  function getTriggerData(ITrigger trigger_) external view returns (Trigger memory) {
    return triggerData[trigger_];
  }

  // -------- Mock setters --------

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) public {
    safetyModuleState = safetyModuleState_;
  }

  function mockSetTriggerData(ITrigger trigger_, Trigger memory triggerData_) public {
    triggerData[trigger_] = triggerData_;
  }

  // -------- Overridden common abstract functions --------

  function dripRewards() public virtual override {
    emit TestRewardsDripped();
  }

  function dripFees() public override {
    emit TestFeesDripped();
  }

  function claimRewards(uint16, /* reservePoolId_ */ address /* receiver_ */ ) public view virtual override {
    __readStub__();
  }

  function _assertValidDepositBalance(
    IERC20, /* token_ */
    uint256, /* tokenPoolBalance_ */
    uint256 /* depositAmount_ */
  ) internal view virtual override {
    __readStub__();
  }

  function _computeNextDripAmount(uint256, /* totalBaseAmount_ */ uint256 /* dripFactor_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _getNextDripAmount(
    uint256, /* totalBaseAmount_ */
    IDripModel, /* dripModel_ */
    uint256, /* lastDripTime_ */
    uint256 /* deltaT_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    uint256, /* stakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view virtual override {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    uint256, /* depositAmount_ */
    uint256 /* slashAmount_ */
  ) internal view virtual override {
    __readStub__();
  }

  function _updateUserRewards(
    uint256, /* userStkTokenBalance_*/
    mapping(uint16 => uint256) storage, /* claimableRewardsIndices_ */
    UserRewardsData[] storage /* userRewards_ */
  ) internal view virtual override {
    __readStub__();
  }
}
