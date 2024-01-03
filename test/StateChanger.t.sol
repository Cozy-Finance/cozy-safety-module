// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../src/interfaces/IERC20.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IStateChangerEvents} from "../src/interfaces/IStateChangerEvents.sol";
import {StateChanger} from "../src/lib/StateChanger.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

interface StateChangerTestMockEvents {
  event DripRewardsCalled();
  event DripFeesCalled();
}

contract StateChangerUnitTest is TestBase, StateChangerTestMockEvents, IStateChangerEvents, ICommonErrors {
  enum TestCaller {
    NONE,
    OWNER,
    PAUSER,
    MANAGER,
    SAFETY_MODULE
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
      new TestableStateChanger(testParams_.owner, testParams_.pauser, IManager(address(manager_)));
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
    else if (testCaller_ == TestCaller.SAFETY_MODULE) testCallerAddress_ = address(component_);
    else testCallerAddress_ = _randomAddress();
  }
}

contract StateChangerPauseTest is StateChangerUnitTest {
  function _testPauseSuccess(ComponentParams memory testParams_, TestCaller testCaller_) internal {
    (TestableStateChanger component_, address caller_) = _initializeComponentAndCaller(testParams_, testCaller_);

    _expectEmit();
    emit DripRewardsCalled();
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
    TestCaller[2] memory invalidCaller_ = [TestCaller.NONE, TestCaller.SAFETY_MODULE];

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
    TestCaller[5] memory callers_ =
      [TestCaller.OWNER, TestCaller.PAUSER, TestCaller.MANAGER, TestCaller.NONE, TestCaller.SAFETY_MODULE];
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
    emit DripRewardsCalled();
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
    TestCaller[5] memory callers_ =
      [TestCaller.OWNER, TestCaller.PAUSER, TestCaller.MANAGER, TestCaller.NONE, TestCaller.SAFETY_MODULE];
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
    TestCaller[3] memory invalidCallers_ = [TestCaller.PAUSER, TestCaller.SAFETY_MODULE, TestCaller.NONE];

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

contract TestableStateChanger is StateChanger, StateChangerTestMockEvents {
  constructor(address owner_, address pauser_, IManager manager_) {
    __initGovernable(owner_, pauser_);
    cozyManager = manager_;
  }

  // -------- Mock setters --------
  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockSetNumPendingSlashes(uint16 numPendingSlashes_) external {
    numPendingSlashes = numPendingSlashes_;
  }

  // -------- Mock getters --------
  function manager() public view returns (IManager) {
    return cozyManager;
  }

  // -------- Overridden abstract function placeholders --------
  function claimRewards(uint16, /* reservePoolId_ */ address receiver_) public view override {
    __readStub__();
  }

  // Mock drip of rewards based on mocked next amount.
  function dripRewards() public override {
    emit DripRewardsCalled();
  }

  function dripFees() public override {
    emit DripFeesCalled();
  }

  function _getNextDripAmount(
    uint256, /* totalBaseAmount_ */
    IDripModel, /* dripModel_ */
    uint256, /* lastDripTime_ */
    uint256 /* deltaT_ */
  ) internal view override returns (uint256) {
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

  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _assertValidDepositBalance(
    IERC20, /* token_ */
    uint256, /* tokenPoolBalance_ */
    uint256 /* depositAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateUserRewards(
    uint256 userStkTokenBalance_,
    mapping(uint16 => uint256) storage claimableRewardsIndices_,
    UserRewardsData[] storage userRewards_
  ) internal override {
    __readStub__();
  }
}
