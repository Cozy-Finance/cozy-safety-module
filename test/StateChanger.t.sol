// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {ICozySafetyModuleManager} from "../src/interfaces/ICozySafetyModuleManager.sol";
import {IStateChangerEvents} from "../src/interfaces/IStateChangerEvents.sol";
import {IStateChangerErrors} from "../src/interfaces/IStateChangerErrors.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {SafetyModuleState, TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {StateChanger} from "../src/lib/StateChanger.sol";
import {ReservePool} from "../src/lib/structs/Pools.sol";
import {Trigger} from "../src/lib/structs/Trigger.sol";
import {MockManager} from "./utils/MockManager.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

interface StateChangerTestMockEvents {
  event DripFeesCalled();
}

contract StateChangerUnitTest is TestBase, StateChangerTestMockEvents, IStateChangerEvents, ICommonErrors {
  enum TestCaller {
    NONE,
    OWNER,
    PAUSER,
    MANAGER
  }

  struct ComponentParams {
    address owner;
    address pauser;
    SafetyModuleState initialState;
    uint16 numPendingSlashes;
  }

  function _initializeComponent(ComponentParams memory testParams_, MockManager manager_)
    internal
    returns (TestableStateChanger)
  {
    TestableStateChanger component_ =
      new TestableStateChanger(testParams_.owner, testParams_.pauser, ICozySafetyModuleManager(address(manager_)));
    component_.mockSetSafetyModuleState(testParams_.initialState);
    component_.mockSetNumPendingSlashes(testParams_.numPendingSlashes);
    return component_;
  }

  function _initializeComponent(ComponentParams memory testParams_) internal returns (TestableStateChanger) {
    return _initializeComponent(testParams_, new MockManager());
  }

  function _initializeComponentAndCaller(ComponentParams memory testParams_, TestCaller testCaller_)
    internal
    returns (TestableStateChanger component_, address testCallerAddress_)
  {
    component_ = _initializeComponent(testParams_);

    if (testCaller_ == TestCaller.OWNER) testCallerAddress_ = testParams_.owner;
    else if (testCaller_ == TestCaller.PAUSER) testCallerAddress_ = testParams_.pauser;
    else if (testCaller_ == TestCaller.MANAGER) testCallerAddress_ = address(component_.manager());
    else testCallerAddress_ = _randomAddress();
  }
}

contract StateChangerPauseTest is StateChangerUnitTest {
  function _testPauseSuccess(ComponentParams memory testParams_, TestCaller testCaller_) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    _expectEmit();
    emit DripFeesCalled();
    _expectEmit();
    emit SafetyModuleStateUpdated(SafetyModuleState.PAUSED);

    vm.prank(caller_);
    component_.pause();

    assertEq(component_.safetyModuleState(), SafetyModuleState.PAUSED);
  }

  function _testPauseInvalidStateTransition(ComponentParams memory testParams_, TestCaller testCaller_) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);
    vm.expectRevert(InvalidStateTransition.selector);
    vm.prank(caller_);
    component_.pause();
  }

  function test_pause() public {
    SafetyModuleState[2] memory validStartStates_ = [SafetyModuleState.ACTIVE, SafetyModuleState.TRIGGERED];
    TestCaller[3] memory validCallers_ = [TestCaller.OWNER, TestCaller.PAUSER, TestCaller.MANAGER];

    for (uint256 i = 0; i < validStartStates_.length; i++) {
      for (uint256 j = 0; j < validCallers_.length; j++) {
        _testPauseSuccess(
          ComponentParams({
            owner: address(0xBEEF),
            pauser: address(0x1331),
            initialState: validStartStates_[i],
            numPendingSlashes: _randomUint16()
          }),
          validCallers_[j]
        );
      }
    }
  }

  function test_pause_invalidStateTransition() public {
    SafetyModuleState[2] memory validStartStates_ = [SafetyModuleState.ACTIVE, SafetyModuleState.TRIGGERED];
    TestCaller[1] memory invalidCaller_ = [TestCaller.NONE];

    for (uint256 i = 0; i < validStartStates_.length; i++) {
      for (uint256 j = 0; j < invalidCaller_.length; j++) {
        _testPauseInvalidStateTransition(
          ComponentParams({
            owner: address(0xBEEF),
            pauser: address(0x1331),
            initialState: validStartStates_[i],
            numPendingSlashes: _randomUint16()
          }),
          invalidCaller_[j]
        );
      }
    }

    // Any call to pause when the Safety Module is already paused should revert.
    TestCaller[4] memory callers_ = [TestCaller.OWNER, TestCaller.PAUSER, TestCaller.MANAGER, TestCaller.NONE];
    for (uint256 i = 0; i < callers_.length; i++) {
      _testPauseInvalidStateTransition(
        ComponentParams({
          owner: address(0xBEEF),
          pauser: address(0x1331),
          initialState: SafetyModuleState.PAUSED,
          numPendingSlashes: _randomUint16()
        }),
        callers_[i]
      );
    }
  }
}

contract StateChangerUnpauseTest is StateChangerUnitTest {
  function _testUnpauseSuccess(
    ComponentParams memory testParams_,
    SafetyModuleState expectedState_,
    TestCaller testCaller_
  ) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    _expectEmit();
    emit DripFeesCalled();
    _expectEmit();
    emit SafetyModuleStateUpdated(expectedState_);

    vm.prank(caller_);
    component_.unpause();

    assertEq(component_.safetyModuleState(), expectedState_);
  }

  function _testUnpauseInvalidStateTransitionRevert(ComponentParams memory testParams_, TestCaller testCaller_)
    internal
  {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    vm.expectRevert(InvalidStateTransition.selector);
    vm.prank(caller_);
    component_.unpause();
  }

  function test_unpause_nonZeroPendingSlashes() public {
    TestCaller[2] memory validCallers_ = [TestCaller.OWNER, TestCaller.MANAGER];
    uint16 numPendingSlashes_ = _randomUint16();
    numPendingSlashes_ = numPendingSlashes_ == 0 ? 1 : numPendingSlashes_;

    for (uint256 i = 0; i < validCallers_.length; i++) {
      _testUnpauseSuccess(
        ComponentParams({
          owner: address(0xBEEF),
          pauser: address(0x1331),
          initialState: SafetyModuleState.PAUSED,
          numPendingSlashes: numPendingSlashes_
        }),
        SafetyModuleState.TRIGGERED,
        validCallers_[i]
      );
    }
  }

  function test_unpause_zeroPendingSlashes() public {
    TestCaller[2] memory validCallers_ = [TestCaller.OWNER, TestCaller.MANAGER];

    for (uint256 i = 0; i < validCallers_.length; i++) {
      _testUnpauseSuccess(
        ComponentParams({
          owner: address(0xBEEF),
          pauser: address(0x1331),
          initialState: SafetyModuleState.PAUSED,
          numPendingSlashes: 0
        }),
        SafetyModuleState.ACTIVE,
        validCallers_[i]
      );
    }
  }

  function test_unpause_revertsWithInvalidStartState() public {
    TestCaller[4] memory callers_ = [TestCaller.OWNER, TestCaller.PAUSER, TestCaller.MANAGER, TestCaller.NONE];
    SafetyModuleState[2] memory invalidStartStates_ = [SafetyModuleState.ACTIVE, SafetyModuleState.TRIGGERED];

    for (uint256 i = 0; i < callers_.length; i++) {
      for (uint256 j = 0; j < invalidStartStates_.length; j++) {
        _testUnpauseInvalidStateTransitionRevert(
          ComponentParams({
            owner: address(0xBEEF),
            pauser: address(0x1331),
            initialState: invalidStartStates_[j],
            numPendingSlashes: _randomUint16()
          }),
          callers_[i]
        );
      }
    }
  }

  function test_unpause_revertsWithInvalidCaller() public {
    TestCaller[2] memory invalidCallers_ = [TestCaller.PAUSER, TestCaller.NONE];

    for (uint256 i = 0; i < invalidCallers_.length; i++) {
      _testUnpauseInvalidStateTransitionRevert(
        ComponentParams({
          owner: address(0xBEEF),
          pauser: address(0x1331),
          initialState: SafetyModuleState.PAUSED,
          numPendingSlashes: _randomUint16()
        }),
        invalidCallers_[i]
      );
    }
  }
}

contract StateChangerTriggerTest is StateChangerUnitTest {
  TestableStateChanger component;
  address mockPayoutHandler;

  function setUp() public {
    component = _initializeComponent(
      ComponentParams({
        owner: address(0xBEEF),
        pauser: address(0x1331),
        initialState: SafetyModuleState.ACTIVE,
        numPendingSlashes: 0
      })
    );

    mockPayoutHandler = _randomAddress();
  }

  function _setUpMockTrigger(TriggerState triggerState_, bool triggered_) internal returns (ITrigger mockTrigger_) {
    mockTrigger_ = ITrigger(address(new MockTrigger(triggerState_)));
    Trigger memory triggerData_ = Trigger({exists: true, payoutHandler: mockPayoutHandler, triggered: triggered_});
    component.mockSetTriggerData(mockTrigger_, triggerData_);
  }

  function _assertTriggerSuccess(ITrigger mockTrigger_) internal {
    SafetyModuleState currState_ = component.safetyModuleState();
    uint256 currNumPendingSlashes_ = component.numPendingSlashes();
    uint256 payoutHandlerCurrNumPendingSlashes_ = component.payoutHandlerNumPendingSlashes(mockPayoutHandler);

    _expectEmit();
    emit DripFeesCalled();
    _expectEmit();
    emit Triggered(mockTrigger_);
    if (currState_ == SafetyModuleState.ACTIVE) {
      _expectEmit();
      emit SafetyModuleStateUpdated(SafetyModuleState.TRIGGERED);
    }

    vm.prank(_randomAddress());
    component.trigger(mockTrigger_);

    // Safety module state only changes if it was ACTIVE before the trigger.
    if (currState_ == SafetyModuleState.ACTIVE) assertEq(component.safetyModuleState(), SafetyModuleState.TRIGGERED);
    else assertEq(component.safetyModuleState(), currState_);

    // The number of pending slashes should always increase by 1.
    assertEq(component.numPendingSlashes(), currNumPendingSlashes_ + 1);
    assertEq(component.payoutHandlerNumPendingSlashes(mockPayoutHandler), payoutHandlerCurrNumPendingSlashes_ + 1);

    // The trigger should be marked as triggered.
    assertEq(component.getTriggerData(mockTrigger_).triggered, true);
  }

  function test_triggerSuccess_activeToTriggered() public {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    // Create a mock trigger that is in TRIGGERED state, but has not triggered the safety module.
    ITrigger mockTrigger_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);
    _assertTriggerSuccess(mockTrigger_);
  }

  function test_triggerSuccess_pausedToPaused() public {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    // Create a mock trigger that is in TRIGGERED state, but has not triggered the safety module.
    ITrigger mockTrigger_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);
    _assertTriggerSuccess(mockTrigger_);
  }

  function test_triggerSuccess_triggeredToTriggered() public {
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);
    // Create a mock trigger that is in TRIGGERED state, but has not triggered the safety module.
    ITrigger mockTrigger_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);
    _assertTriggerSuccess(mockTrigger_);
  }

  function testFuzz_trigger_invalidTriggerDoesNotExist(ITrigger invalidTrigger_) public {
    // Create a mock trigger that is in TRIGGERED state, but has not triggered the safety module.
    ITrigger mockTrigger_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);

    // `invalidTrigger_` data does not exist, so cannot trigger the safety module.
    vm.assume(address(invalidTrigger_) != address(mockTrigger_));
    vm.expectRevert(IStateChangerErrors.InvalidTrigger.selector);
    component.trigger(invalidTrigger_);
  }

  function test_trigger_invalidTriggerState() public {
    // Create a mock trigger that is in ACTIVE state and has not triggered the safety module.
    ITrigger mockTrigger_ = _setUpMockTrigger(TriggerState.ACTIVE, false);

    vm.expectRevert(IStateChangerErrors.InvalidTrigger.selector);
    component.trigger(mockTrigger_);
  }

  function test_trigger_triggerAlreadyTriggered() public {
    // Create a mock trigger that is in TRIGGERED state and has already triggered the safety module.
    ITrigger mockTrigger_ = _setUpMockTrigger(TriggerState.TRIGGERED, true);

    vm.expectRevert(IStateChangerErrors.InvalidTrigger.selector);
    component.trigger(mockTrigger_);
  }

  function test_multipleTriggerSuccess_activeToTriggered() public {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    // Create two mock triggers that are in TRIGGERED state and have not triggered the safety module.
    ITrigger mockTriggerA_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);
    ITrigger mockTriggerB_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);

    _assertTriggerSuccess(mockTriggerA_);
    _assertTriggerSuccess(mockTriggerB_);
  }

  function test_multipleTriggerSuccess_pausedToPaused() public {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    // Create two mock triggers that are in TRIGGERED state and have not triggered the safety module.
    ITrigger mockTriggerA_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);
    ITrigger mockTriggerB_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);

    _assertTriggerSuccess(mockTriggerA_);
    _assertTriggerSuccess(mockTriggerB_);
  }

  function test_multipleTriggerSuccess_triggeredToTriggered() public {
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);

    // Create two mock triggers that are in TRIGGERED state and have not triggered the safety module.
    ITrigger mockTriggerA_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);
    ITrigger mockTriggerB_ = _setUpMockTrigger(TriggerState.TRIGGERED, false);

    _assertTriggerSuccess(mockTriggerA_);
    _assertTriggerSuccess(mockTriggerB_);
  }
}

contract TestableStateChanger is StateChanger, StateChangerTestMockEvents {
  constructor(address owner_, address pauser_, ICozySafetyModuleManager manager_) {
    __initGovernable(owner_, pauser_);
    cozySafetyModuleManager = manager_;
  }

  // -------- Mock setters --------
  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockSetNumPendingSlashes(uint16 numPendingSlashes_) external {
    numPendingSlashes = numPendingSlashes_;
  }

  function mockSetTriggerData(ITrigger trigger_, Trigger memory triggerData_) public {
    triggerData[trigger_] = triggerData_;
  }

  // -------- Mock getters --------
  function manager() public view returns (ICozySafetyModuleManager) {
    return cozySafetyModuleManager;
  }

  function getTriggerData(ITrigger trigger_) external view returns (Trigger memory) {
    return triggerData[trigger_];
  }

  // -------- Overridden abstract function placeholders --------

  function dripFees() public override {
    emit DripFeesCalled();
  }

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /* lastDripTime_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function convertToReceiptTokenAmount(uint8, /* reservePoolId_ */ uint256 /*reserveAssetAmount_ */ )
    public
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function convertToReserveAssetAmount(uint8, /* reservePoolId_ */ uint256 /* depositReceiptTokenAmount_ */ )
    public
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint8, /* reservePoolId_ */
    ReservePool storage, /* reservePool_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _dripFeesFromReservePool(ReservePool storage, /*reservePool_*/ IDripModel /*dripModel_*/ )
    internal
    view
    override
  {
    __readStub__();
  }
}
