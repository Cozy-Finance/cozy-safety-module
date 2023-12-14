// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "forge-std/console2.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IStkToken} from "../src/interfaces/IStkToken.sol";
import {IDepositToken} from "../src/interfaces/IDepositToken.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IUnstakerErrors} from "../src/interfaces/IUnstakerErrors.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {CozyMath} from "../src/lib/CozyMath.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {Unstaker} from "../src/lib/Unstaker.sol";
import {UnstakerLib} from "../src/lib/UnstakerLib.sol";
import {StkToken} from "../src/StkToken.sol";
import {StkTokenFactory} from "../src/StkTokenFactory.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {ReservePool} from "../src/lib/structs/Pools.sol";
import {TokenPool} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

contract UnstakerUnitTest is TestBase {
  using CozyMath for uint256;
  using FixedPointMathLib for uint256;

  IStkToken stkToken;
  MockManager public mockManager = new MockManager();
  TestableUnstaker component = new TestableUnstaker(IManager(address(mockManager)));
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
  MockERC20 mockDepositToken = new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6);

  uint256 internal constant UNSTAKE_DELAY = 15 days;

  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint256 stkTokenAmount_,
    uint256 reserveTokenAmount_,
    uint64 unstakeId_
  );

  event UnstakePending(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint256 stkTokenAmount_,
    uint256 reserveTokenAmount,
    uint64 unstakeId_
  );

  event Transfer(address indexed from, address indexed to, uint256 amount);

  function setUp() public {
    component.mockSetUnstakeDelay(UNSTAKE_DELAY);

    StkToken stkTokenLogic_ = new StkToken(IManager(address(mockManager)));
    stkTokenLogic_.initialize(ISafetyModule(address(0)), 0);
    StkTokenFactory stkTokenFactory = new StkTokenFactory(IStkToken(address(stkTokenLogic_)));

    vm.prank(address(component));
    stkToken = IStkToken(address(stkTokenFactory.deployStkToken(0, 18)));
    vm.stopPrank();

    component.mockAddReservePool(
      ReservePool({
        token: IERC20(address(mockAsset)),
        stkToken: IStkToken(address(stkToken)),
        depositToken: IDepositToken(address(mockDepositToken)),
        stakeAmount: 0,
        depositAmount: 0
      })
    );
    component.mockAddTokenPool(IERC20(address(mockAsset)), TokenPool({balance: 0}));
  }

  function test_unstake_canUnstakeAllInstantly_whenUnstakeDelayIsZero() external {
    component.mockSetUnstakeDelay(0);

    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    _expectEmit();
    emit Transfer(staker_, address(0), stkTokenAmount_);
    _expectEmit();
    emit Unstaked(staker_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);

    vm.prank(staker_);
    (uint64 resultUnstakeId_, uint256 resultReserveTokenAmount_) =
      component.unstake(0, stkTokenAmount_, receiver_, staker_);

    assertEq(resultUnstakeId_, nextUnstakeId_, "unstakeId");
    assertEq(resultReserveTokenAmount_, amountStaked_, "reserve token assets received");
    assertEq(stkToken.balanceOf(staker_), 0, "shares balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), resultReserveTokenAmount_, "reserve token assets balanceOf");
    assertEq(component.getUnstakeIdCounter(), 1, "unstakeIdCounter");
  }

  function test_unstake_canUnstakeAllInstantly_whenSafetyModuleIsPaused() external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    _expectEmit();
    emit Unstaked(staker_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    vm.prank(staker_);
    component.unstake(0, stkTokenAmount_, receiver_, staker_);
  }

  function test_unstake_canUnstakePartialInstantly() external {
    component.mockSetUnstakeDelay(0);

    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    uint256 stkTokensToUnstake_ = stkTokenAmount_ / 2 - 1;
    uint256 reserveAssetsToReceive_ = uint256(amountStaked_).mulDivDown(stkTokensToUnstake_, stkTokenAmount_);

    _expectEmit();
    emit Transfer(staker_, address(0), stkTokensToUnstake_);
    _expectEmit();
    emit Unstaked(staker_, receiver_, staker_, stkTokensToUnstake_, reserveAssetsToReceive_, nextUnstakeId_);

    vm.prank(staker_);
    (uint64 resultUnstakeId_, uint256 resultReserveTokenAmount_) =
      component.unstake(0, stkTokensToUnstake_, receiver_, staker_);

    assertEq(resultUnstakeId_, nextUnstakeId_, "unstakeId");
    assertEq(resultReserveTokenAmount_, reserveAssetsToReceive_, "reserve token assets received");
    assertEq(stkToken.balanceOf(staker_), stkTokenAmount_ - stkTokensToUnstake_, "shares balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetsToReceive_, "reserve token assets balanceOf");
    assertEq(component.getUnstakeIdCounter(), 1, "unstakeIdCounter");
  }

  function test_unstake_canUnstakeTotalInstantlyInTwoUnstakes() external {
    component.mockSetUnstakeDelay(0);

    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    uint256 stkTokensToUnstake_ = stkTokenAmount_ / 2 - 1;
    uint256 reserveAssetsToReceive_ = uint256(amountStaked_).mulDivDown(stkTokensToUnstake_, stkTokenAmount_);

    _expectEmit();
    emit Transfer(staker_, address(0), stkTokensToUnstake_);
    _expectEmit();
    emit Unstaked(staker_, receiver_, staker_, stkTokensToUnstake_, reserveAssetsToReceive_, nextUnstakeId_);

    vm.prank(staker_);
    (uint64 resultUnstakeId_, uint256 resultReserveTokenAmount_) =
      component.unstake(0, stkTokensToUnstake_, receiver_, staker_);

    assertEq(resultUnstakeId_, nextUnstakeId_, "unstakeId");
    assertEq(resultReserveTokenAmount_, reserveAssetsToReceive_, "reserve token assets received");
    assertEq(stkToken.balanceOf(staker_), stkTokenAmount_ - stkTokensToUnstake_, "shares balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetsToReceive_, "reserve token assets balanceOf");
    assertEq(component.getUnstakeIdCounter(), 1, "unstakeIdCounter");

    stkTokensToUnstake_ = stkTokenAmount_ - stkTokensToUnstake_;
    reserveAssetsToReceive_ = amountStaked_ - reserveAssetsToReceive_;
    nextUnstakeId_ += 1;

    _expectEmit();
    emit Transfer(staker_, address(0), stkTokensToUnstake_);
    _expectEmit();
    emit Unstaked(staker_, receiver_, staker_, stkTokensToUnstake_, reserveAssetsToReceive_, nextUnstakeId_);

    vm.prank(staker_);
    (resultUnstakeId_, resultReserveTokenAmount_) = component.unstake(0, stkTokensToUnstake_, receiver_, staker_);

    assertEq(resultUnstakeId_, nextUnstakeId_, "unstakeId");
    assertEq(resultReserveTokenAmount_, reserveAssetsToReceive_, "reserve token assets received");
    assertEq(stkToken.balanceOf(staker_), 0, "shares balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), amountStaked_, "reserve token assets balanceOf");
    assertEq(component.getUnstakeIdCounter(), 2, "unstakeIdCounter");
  }

  function test_unstake_cannotUnstakeIfSafetyModuleTriggered() external {
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(staker_);
    component.unstake(0, stkTokenAmount_, receiver_, staker_);
  }

  function test_unstake_cannotUnstakeMoreStkTokensThanOwned() external {
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    // Stake some extra that belongs to someone else.
    _stake(0, _randomAddress(), 1e6, 1e18);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(staker_);
    component.unstake(0, stkTokenAmount_ + 1, receiver_, staker_);
  }

  function test_unstake_cannotUnstakeIfRoundsDownToZeroAssets() external {
    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToStake_ = 1;
    uint256 stkTokenAmount_ = 3;
    _stake(0, staker_, amountToStake_, stkTokenAmount_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(staker_);
    component.unstake(0, 2, receiver_, staker_);
  }

  function test_unstake_canUnstakeAllInstantly_ThroughAllowance() external {
    component.mockSetUnstakeDelay(0);

    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);
    address spender_ = _randomAddress();
    vm.prank(staker_);
    stkToken.approve(spender_, stkTokenAmount_ + 1); // Allowance is 1 extra.

    _expectEmit();
    emit Unstaked(spender_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);

    vm.prank(spender_);
    component.unstake(0, stkTokenAmount_, receiver_, staker_);
    assertEq(stkToken.allowance(staker_, spender_), 1, "stkToken allowance"); // Only 1 allowance left because of
      // subtraction.
  }

  function test_unstake_cannotUnstake_ThroughAllowance_WithInsufficientAllowance() external {
    component.mockSetUnstakeDelay(0);

    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);
    address spender_ = _randomAddress();
    vm.prank(staker_);
    stkToken.approve(spender_, stkTokenAmount_ - 1); // Allowance is 1 less.

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(spender_);
    component.unstake(0, stkTokenAmount_, receiver_, staker_);
  }

  function test_unstake_canQueueUnstakeAll_ThenCompleteAfterDelay() external {
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit UnstakePending(staker_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    vm.prank(staker_);
    {
      (uint64 resultUnstakeId_, uint256 resultUnstakedAssets_) =
        component.unstake(0, stkTokenAmount_, receiver_, staker_);
      assertEq(resultUnstakeId_, nextUnstakeId_, "redemptionId");
      assertEq(resultUnstakedAssets_, amountStaked_, "redeemed assets");
    }

    skip(component.unstakeDelay());
    // Complete.
    _expectEmit();
    emit Unstaked(address(this), receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    component.completeUnstake(nextUnstakeId_);

    assertEq(stkToken.balanceOf(staker_), 0, "stkToken balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), amountStaked_, "assets balanceOf");
  }

  function test_unstake_canQueueUnstakeAll_ThenCompleteIfSafetyModuleIsPaused() external {
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit UnstakePending(staker_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    vm.prank(staker_);
    {
      (uint64 resultUnstakeId_, uint256 resultUnstakedAssets_) =
        component.unstake(0, stkTokenAmount_, receiver_, staker_);
      assertEq(resultUnstakeId_, nextUnstakeId_, "redemptionId");
      assertEq(resultUnstakedAssets_, amountStaked_, "redeemed assets");
    }

    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    // Complete.
    _expectEmit();
    emit Unstaked(address(this), receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    component.completeUnstake(nextUnstakeId_);

    assertEq(stkToken.balanceOf(staker_), 0, "stkToken balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), amountStaked_, "assets balanceOf");
  }

  function test_unstake_delayedUnstakeAll_IsNotAffectedByNewStake() external {
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit UnstakePending(staker_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    vm.prank(staker_);
    component.unstake(0, stkTokenAmount_, receiver_, staker_);

    // New stake.
    _stake(0, _randomAddress(), 1e6, 1e18);

    skip(component.unstakeDelay());
    // Complete.
    _expectEmit();
    emit Unstaked(address(this), receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    component.completeUnstake(nextUnstakeId_);

    assertEq(stkToken.balanceOf(staker_), 0, "stkToken balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), amountStaked_, "assets balanceOf");
  }

  function test_unstake_cannotCompleteUnstakeBeforeDelayPasses() external {
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit UnstakePending(staker_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    vm.prank(staker_);
    component.unstake(0, stkTokenAmount_, receiver_, staker_);

    skip(component.unstakeDelay() - 1);
    // Complete.
    vm.expectRevert(IUnstakerErrors.DelayNotElapsed.selector);
    component.completeUnstake(nextUnstakeId_);
  }

  function test_unstake_cannotCompleteUnstakeSameUnstakeIdTwice() external {
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit UnstakePending(staker_, receiver_, staker_, stkTokenAmount_, amountStaked_, nextUnstakeId_);
    vm.prank(staker_);
    component.unstake(0, stkTokenAmount_, receiver_, staker_);

    skip(component.unstakeDelay());
    // Complete.
    component.completeUnstake(nextUnstakeId_);
    vm.expectRevert(IUnstakerErrors.UnstakeNotFound.selector);
    component.completeUnstake(nextUnstakeId_);
  }

  function test_unstake_triggerCanReduceExchangeRateForPendingUnstakes() external {
    (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_) =
      _setupDefaultSingleUserFixture(0);
    uint256 stkTokensToUnstake = stkTokenAmount_; // Unstake 1/4 of all stkTokens.
    uint256 oldReservePoolAmount_ = amountStaked_;
    uint256 slashAmount_ = oldReservePoolAmount_ / 10; // Slash 1/10 of the reserve pool.

    // Queue.
    vm.prank(staker_);
    (, uint256 reserveTokensToReceive_) = component.unstake(0, stkTokensToUnstake, receiver_, staker_);
    assertEq(
      reserveTokensToReceive_, stkTokensToUnstake.mulDivDown(amountStaked_, stkTokenAmount_), "reserveTokensToReceive"
    );

    // Trigger, slashing 1/10 of the reserve pool.
    component.updateUnstakesAfterTrigger(0, oldReservePoolAmount_, slashAmount_);

    skip(component.unstakeDelay());
    uint256 reserveTokensReceived_ = component.completeUnstake(nextUnstakeId_);
    // stkTokens are now worth 90% of what they were before the trigger.
    assertEq(reserveTokensReceived_, reserveTokensToReceive_ * 9 / 10 - 1, "assets redeemed");
    assertEq(stkToken.balanceOf(staker_), 0, "shares balanceOf");
  }

  function test_unstake_triggerWhileNoneBeingUnstaked() external {
    uint256 assets_ = 100e18;
    // Trigger, taking 10% out of reserve pool.
    component.updateUnstakesAfterTrigger(0, assets_, assets_ / 10);
  }

  function test_unstake_triggerAddsFirstAccumulatorEntry() external {
    uint256 assets_ = 100e18;
    uint256[] memory accs_ = component.getPendingUnstakesAccISFs(0);
    assertEq(accs_.length, 0, "accs_.length == 0");
    // Trigger, taking 10% out of pool.
    component.updateUnstakesAfterTrigger(0, assets_, assets_ / 10);
    accs_ = component.getPendingUnstakesAccISFs(0);
    assertEq(accs_.length, 1, "accs_.length == 1");
    assertEq(accs_[0], MathConstants.WAD * 10 / 9 + 1, "accs_[0]");
  }

  function test_unstake_triggerCanUpdateLastAccumulatorEntry() external {
    uint256 assets_ = 100e18;
    // Trigger, taking 10% out of pool.
    component.updateUnstakesAfterTrigger(0, assets_, assets_ / 10);
    uint256[] memory accs_ = component.getPendingUnstakesAccISFs(0);
    assertEq(accs_.length, 1, "accs_.length");
    assertEq(accs_[0], MathConstants.WAD.mulDivUp(10, 9), "accs_[0]");

    uint256 firstAcc_ = accs_[0];

    // Trigger, taking 25% out of pool.
    component.updateUnstakesAfterTrigger(0, assets_, assets_ / 4);
    accs_ = component.getPendingUnstakesAccISFs(0);
    assertEq(accs_.length, 1, "accs_.length");
    assertEq(accs_[0], firstAcc_.mulWadUp(MathConstants.WAD.mulDivUp(4, 3)), "accs_[0]");
  }

  function test_unstake_triggerCanAddNewAccumulatorEntry() external {
    uint256 assets_ = 100e18;
    // We should be able to exceed NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD and require a new entry
    // with 2 100% losses.

    // Trigger, taking 100% out of collateral.
    component.updateUnstakesAfterTrigger(0, assets_, assets_);
    // Trigger, taking 100% out of collateral.
    component.updateUnstakesAfterTrigger(0, assets_, assets_);

    uint256 expectedAcc0_ = UnstakerLib.INF_INV_SCALING_FACTOR.mulWadDown(UnstakerLib.INF_INV_SCALING_FACTOR) + 1;
    uint256[] memory accs_ = component.getPendingUnstakesAccISFs(0);
    assertEq(accs_.length, 2, "accs_.length");
    assertEq(accs_[0], expectedAcc0_, "accs_[0]");
    assertEq(accs_[1], MathConstants.WAD, "accs_[1]");

    // Trigger, taking 33% out of collateral.
    component.updateUnstakesAfterTrigger(0, assets_, assets_ * 33 / 100);
    accs_ = component.getPendingUnstakesAccISFs(0);
    assertEq(accs_.length, 2, "accs_.length");
    assertEq(accs_[0], expectedAcc0_, "accs_[0]");
    assertEq(accs_[1], MathConstants.WAD * 100 / 67 + 1, "accs_[1]");
  }

  function testFuzz_unstake_updateUnstakesAfterTrigger(
    uint256 acc_,
    uint256 oldReservePoolAmount_,
    uint256 slashAmount_,
    uint256 unstakes_
  ) external {
    acc_ = bound(acc_, MathConstants.WAD, UnstakerLib.NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD);
    oldReservePoolAmount_ = bound(oldReservePoolAmount_, 0, type(uint128).max);
    slashAmount_ = bound(slashAmount_, 0, type(uint128).max);
    unstakes_ = bound(unstakes_, 0, type(uint128).max);
    uint256 claimable_ = oldReservePoolAmount_ + unstakes_;
    component.mockSetLastAccISF(0, acc_);
    component.updateUnstakesAfterTrigger(0, oldReservePoolAmount_, slashAmount_);

    uint256 scale_;
    if (oldReservePoolAmount_ >= slashAmount_ && oldReservePoolAmount_ != 0) {
      scale_ = MathConstants.WAD - slashAmount_.divWadDown(oldReservePoolAmount_);
    }
    uint256[] memory accs_ = component.getPendingUnstakesAccISFs(0);
    if (accs_[0] > UnstakerLib.NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD) assertEq(accs_.length, 2, "accs_.length");
    else assertEq(accs_.length, 1, "accs_.length");
    if (scale_ != 0) assertEq(accs_[0], acc_.mulWadUp(MathConstants.WAD.divWadUp(scale_)), "accs_[0]");
    else assertEq(accs_[0], acc_.mulWadUp(UnstakerLib.INF_INV_SCALING_FACTOR), "accs_[0]");
  }

  // TODO: Fuzz tests for multiple redeems
  struct FuzzUserInfo {
    address staker;
    address receiver;
    uint216 stkTokenAmount;
    uint64 unstakeId;
    uint128 assetsUnstaked;
    uint216 stkTokensUnstaked;
  }

  // TODO: Preview tests

  function _stake(uint16 reservePoolId_, address staker_, uint256 amountToStake_, uint256 stkTokenAmount_) private {
    component.mockStake(reservePoolId_, staker_, amountToStake_, stkTokenAmount_);
  }

  function _setupDefaultSingleUserFixture(uint16 reservePoolId_)
    private
    returns (address staker_, address receiver_, uint256 amountStaked_, uint256 stkTokenAmount_, uint64 nextUnstakeId_)
  {
    staker_ = _randomAddress();
    receiver_ = _randomAddress();
    amountStaked_ = 1e6;
    stkTokenAmount_ = 1e18;
    nextUnstakeId_ = component.getUnstakeIdCounter();
    _stake(reservePoolId_, staker_, amountStaked_, stkTokenAmount_);
  }
}

contract TestableUnstaker is Unstaker {
  MockManager public immutable mockManager;

  constructor(IManager manager_) {
    mockManager = MockManager(address(manager_));
  }

  function mockStake(uint16 reservePoolId_, address staker_, uint256 amountToStake_, uint256 stkTokenAmount_) external {
    mockStakeAssets(reservePoolId_, amountToStake_);
    mockMintStkTokens(reservePoolId_, staker_, stkTokenAmount_);
  }

  function mockStakeAssets(uint16 reservePoolId_, uint256 amountToStake_) public {
    if (amountToStake_ > 0) {
      ReservePool storage reservePool_ = reservePools[reservePoolId_];
      MockERC20(address(reservePool_.token)).mint(address(this), amountToStake_);
      reservePool_.stakeAmount += amountToStake_;
      tokenPools[reservePool_.token].balance += amountToStake_;
    }
  }

  function mockMintStkTokens(uint16 reservePoolId_, address staker_, uint256 stkTokenAmount_) public {
    if (stkTokenAmount_ > 0) MockERC20(address(reservePools[reservePoolId_].stkToken)).mint(staker_, stkTokenAmount_);
  }

  // -------- Mock setters --------
  function mockSetUnstakeDelay(uint256 unstakeDelay_) external {
    unstakeDelay = unstakeDelay_;
  }

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) public {
    reservePools.push(reservePool_);
  }

  function mockAddTokenPool(IERC20 token_, TokenPool memory tokenPool_) public {
    tokenPools[token_] = tokenPool_;
  }

  function mockSetLastAccISF(uint16 reservePoolId_, uint256 acc_) external {
    uint256[] storage pendingUnstakesAccISFs_ = pendingUnstakesAccISFs[reservePoolId_];
    if (pendingUnstakesAccISFs_.length == 0) pendingUnstakesAccISFs_.push(acc_);
    else pendingUnstakesAccISFs_[pendingUnstakesAccISFs_.length - 1] = acc_;
  }
  // -------- Mock getters --------

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getTokenPool(IERC20 token_) external view returns (TokenPool memory) {
    return tokenPools[token_];
  }

  function getUnstakeIdCounter() external view returns (uint64) {
    return unstakeIdCounter;
  }

  function getPendingUnstakesAccISFs(uint16 reservePoolId_) external view returns (uint256[] memory) {
    return pendingUnstakesAccISFs[reservePoolId_];
  }

  // -------- Exposed internals --------

  function updateUnstakesAfterTrigger(uint16 reservePoolId_, uint256 oldStakeAmount_, uint256 slashAmount_) external {
    _updateUnstakesAfterTrigger(reservePoolId_, uint128(oldStakeAmount_), uint128(slashAmount_));
  }
}
