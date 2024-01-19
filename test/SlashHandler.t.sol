// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Ownable} from "../src/lib/Ownable.sol";
import {ReceiptToken} from "../src/ReceiptToken.sol";
import {ReceiptTokenFactory} from "../src/ReceiptTokenFactory.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ISlashHandlerErrors} from "../src/interfaces/ISlashHandlerErrors.sol";
import {SlashHandler} from "../src/lib/SlashHandler.sol";
import {Redeemer} from "../src/lib/Redeemer.sol";
import {SafeCastLib} from "../src/lib/SafeCastLib.sol";
import {UserRewardsData, ClaimableRewardsData} from "../src/lib/structs/Rewards.sol";
import {SafetyModuleState, TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {AssetPool, ReservePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {Slash} from "../src/lib/structs/Slash.sol";
import {Trigger} from "../src/lib/structs/Trigger.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

contract TriggerHandlerTest is TestBase {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  TestableSlashHandler component;
  address mockPayoutHandler;

  MockManager public mockManager = new MockManager();
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);

  function setUp() public {
    component = new TestableSlashHandler();
    mockPayoutHandler = _randomAddress();

    component.mockSetPayoutHandlerNumPendingSlashes(mockPayoutHandler, 1);
    component.mockSetNumPendingSlashes(1);
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);
  }

  function _getScalingFactor(uint256 oldPoolAmount_, uint256 slashAmount_) internal pure returns (uint256) {
    if (slashAmount_ > oldPoolAmount_) return 0;
    if (oldPoolAmount_ == 0) return 0;
    return MathConstants.WAD - slashAmount_.divWadDown(oldPoolAmount_);
  }

  function _testSingleSlashSuccess(uint128 stakeAmount_, uint128 depositAmount_, uint128 slashAmount_) internal {
    address receiver_ = _randomAddress();
    uint256 pendingUnstakesAmount_ = bound(_randomUint256(), 0, stakeAmount_);
    uint256 pendingWithdrawalsAmount_ = bound(_randomUint256(), 0, depositAmount_);
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 1e4,
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: stakeAmount_ + depositAmount_}));
    mockAsset.mint(address(component), stakeAmount_ + depositAmount_);

    Slash[] memory slashes_ = new Slash[](1);
    slashes_[0] = Slash({reservePoolId: 0, amount: slashAmount_});

    if (slashAmount_ > 0) {
      _expectEmit();
      emit IERC20.Transfer(address(component), receiver_, slashAmount_);
    }
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);

    ReservePool memory reservePool_ = component.getReservePool(0);
    if (slashAmount_ >= depositAmount_) {
      uint256 remainingSlashAmount_ = slashAmount_ - depositAmount_;
      assertEq(reservePool_.depositAmount, 0, "depositAmount");
      assertEq(reservePool_.stakeAmount, stakeAmount_ - remainingSlashAmount_, "stakeAmount");
      assertEq(reservePool_.pendingWithdrawalsAmount, 0, "pendingWithdrawalsAmount");
      assertEq(
        reservePool_.pendingUnstakesAmount,
        pendingUnstakesAmount_.mulWadDown(_getScalingFactor(stakeAmount_, remainingSlashAmount_)),
        "pendingUnstakesAmount"
      );
    } else {
      assertEq(reservePool_.depositAmount, depositAmount_ - slashAmount_, "depositAmount");
      assertEq(reservePool_.stakeAmount, stakeAmount_, "stakeAmount");
      assertEq(
        reservePool_.pendingWithdrawalsAmount,
        pendingWithdrawalsAmount_.mulWadDown(_getScalingFactor(depositAmount_, slashAmount_)),
        "pendingWithdrawalsAmount"
      );
      assertEq(reservePool_.pendingUnstakesAmount, pendingUnstakesAmount_, "pendingUnstakesAmount");
    }
    assertEq(component.assetPools(IERC20(address(mockAsset))), stakeAmount_ + depositAmount_ - slashAmount_);
    assertEq(mockAsset.balanceOf(receiver_), slashAmount_);
    assertEq(component.numPendingSlashes(), 0);
    assertEq(component.payoutHandlerNumPendingSlashes(mockPayoutHandler), 0);
    assertEq(component.safetyModuleState(), SafetyModuleState.ACTIVE);
  }

  function test_slash_entireReservePool() public {
    _testSingleSlashSuccess(20e6, 10e6, 30e6);
  }

  function test_slash_allDepositsPartialStakes() public {
    _testSingleSlashSuccess(20e6, 10e6, 25e6);
  }

  function test_slash_partialDepositsNoStakes() public {
    _testSingleSlashSuccess(20e6, 10e6, 5e6);
  }

  function test_slash_noAssets() public {
    _testSingleSlashSuccess(20e6, 10e6, 0);
  }

  function test_slash_multipleReservePools() public {
    component.mockSetPayoutHandlerNumPendingSlashes(mockPayoutHandler, 3);
    component.mockSetNumPendingSlashes(6);
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);

    uint128 stakeAmount_ = 100e6;
    uint128 depositAmount_ = 200e6;
    uint128 pendingUnstakesAmount_ = 50e6;
    uint128 pendingWithdrawalsAmount_ = 100e6;
    // Slash all deposited assets and some staked assets from pool 0.
    uint128 slashAmountA_ = 250e6;
    // Slash some deposited assets and no staked assets from pool 1.
    uint128 slashAmountB_ = 50e6;
    // Slash no assets from pool 2.
    uint128 slashAmountC_ = 0;

    address receiver_ = _randomAddress();
    // Reserve pool 0.
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 0.25e4,
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    // Reserve pool 1.
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 0.25e4,
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    // Reserve pool 2.
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 0.5e4,
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: (stakeAmount_ + depositAmount_) * 3}));
    // Mint safety module rewards.
    mockAsset.mint(address(component), 3 * (stakeAmount_ + depositAmount_));

    Slash[] memory slashes_ = new Slash[](3);
    slashes_[0] = Slash({reservePoolId: 0, amount: slashAmountA_});
    slashes_[1] = Slash({reservePoolId: 1, amount: slashAmountB_});
    slashes_[2] = Slash({reservePoolId: 2, amount: slashAmountC_});

    // Reserve pool 0 slash events. The staked assets are slashed after the deposited assets.
    _expectEmit();
    emit IERC20.Transfer(address(component), receiver_, slashAmountA_);

    // Reserve pool 1 slash events. The staked assets are not slashed because the deposit amount is sufficient.
    _expectEmit();
    emit IERC20.Transfer(address(component), receiver_, slashAmountB_);

    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);

    // Reserve pool 0 - all deposited assets and some staked assets are slashed.
    ReservePool memory reservePool_ = component.getReservePool(0);
    assertEq(reservePool_.depositAmount, 0);
    assertEq(reservePool_.stakeAmount, stakeAmount_ - (slashAmountA_ - depositAmount_));
    assertEq(
      reservePool_.pendingUnstakesAmount,
      uint256(pendingUnstakesAmount_).mulWadDown(
        _getScalingFactor(stakeAmount_, stakeAmount_ - (slashAmountA_ - depositAmount_))
      )
    );
    assertEq(reservePool_.pendingWithdrawalsAmount, 0);

    // Reserve pool 1 - some deposited assets and no staked assets are slashed.
    reservePool_ = component.getReservePool(1);
    assertEq(reservePool_.depositAmount, depositAmount_ - slashAmountB_);
    assertEq(reservePool_.stakeAmount, stakeAmount_);
    assertEq(reservePool_.pendingUnstakesAmount, pendingUnstakesAmount_);
    assertEq(
      reservePool_.pendingWithdrawalsAmount,
      uint256(pendingWithdrawalsAmount_).mulWadDown(_getScalingFactor(depositAmount_, slashAmountB_))
    );

    // Reserve pool 2 - no assets are slashed.
    reservePool_ = component.getReservePool(2);
    assertEq(reservePool_.depositAmount, depositAmount_);
    assertEq(reservePool_.stakeAmount, stakeAmount_);
    assertEq(reservePool_.pendingUnstakesAmount, pendingUnstakesAmount_);
    assertEq(reservePool_.pendingWithdrawalsAmount, pendingWithdrawalsAmount_);

    // Aggregate balance and safety module state.
    assertEq(
      component.assetPools(IERC20(address(mockAsset))),
      (3 * (stakeAmount_ + depositAmount_)) - (slashAmountA_ + slashAmountB_ + slashAmountC_)
    );
    assertEq(mockAsset.balanceOf(receiver_), slashAmountA_ + slashAmountB_ + slashAmountC_);
    assertEq(component.numPendingSlashes(), 5);
    assertEq(component.payoutHandlerNumPendingSlashes(mockPayoutHandler), 2);
    assertEq(component.safetyModuleState(), SafetyModuleState.TRIGGERED); // Still triggered because there are pending
      // slashes.
  }

  function test_slash_revert_noPendingSlashes() public {
    component.mockSetPayoutHandlerNumPendingSlashes(mockPayoutHandler, 0);

    Slash[] memory slashes_ = new Slash[](1);
    slashes_[0] = Slash({reservePoolId: 0, amount: 1});

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, _randomAddress());
  }

  function test_slash_revert_safetyModuleNotTriggered() public {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    Slash[] memory slashes_ = new Slash[](1);
    slashes_[0] = Slash({reservePoolId: 0, amount: 1});

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, _randomAddress());
  }

  function test_slash_revert_insufficientReserveAssets() public {
    uint128 stakeAmount_ = 100e6;
    uint128 depositAmount_ = 200e6;
    uint128 pendingUnstakesAmount_ = 50e6;
    uint128 pendingWithdrawalsAmount_ = 100e6;
    uint128 slashAmountA_ = 250e6;
    uint128 slashAmountB_ = 251e6;

    address receiver_ = _randomAddress();
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 0.5e4,
        maxSlashPercentage: 0.5e18,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 0.5e4,
        maxSlashPercentage: 0.49e18,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: (stakeAmount_ + depositAmount_) * 2}));
    // Mint safety module reserve assets.
    mockAsset.mint(address(component), (stakeAmount_ + depositAmount_) * 2);

    Slash[] memory slashes_ = new Slash[](2);
    slashes_[0] = Slash({reservePoolId: 0, amount: slashAmountA_});
    slashes_[1] = Slash({reservePoolId: 1, amount: slashAmountB_});

    uint256 slashPercentage_ = uint256(slashAmountB_ - depositAmount_).divWadUp(stakeAmount_);
    vm.expectRevert(abi.encodeWithSelector(ISlashHandlerErrors.ExceedsMaxSlashPercentage.selector, 1, slashPercentage_));
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);
  }

  function test_slash_revert_alreadySlashed() public {
    uint128 stakeAmount_ = 100e6;
    uint128 depositAmount_ = 200e6;
    uint128 pendingUnstakesAmount_ = 50e6;
    uint128 pendingWithdrawalsAmount_ = 100e6;
    uint128 slashAmount_ = 1e6;

    address receiver_ = _randomAddress();
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 0.5e4,
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        rewardsPoolsWeight: 0.5e4,
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: (stakeAmount_ + depositAmount_) * 2}));
    // Mint safety module reserve assets.
    mockAsset.mint(address(component), (stakeAmount_ + depositAmount_) * 2);

    Slash[] memory slashes_ = new Slash[](3);
    slashes_[0] = Slash({reservePoolId: 1, amount: slashAmount_});
    slashes_[1] = Slash({reservePoolId: 0, amount: slashAmount_});
    slashes_[2] = Slash({reservePoolId: 1, amount: slashAmount_});

    vm.expectRevert(abi.encodeWithSelector(ISlashHandlerErrors.AlreadySlashed.selector, 1));
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);
  }
}

contract TestableSlashHandler is SlashHandler, Redeemer {
  // -------- Getters --------

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  // -------- Mock setters --------

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) public {
    safetyModuleState = safetyModuleState_;
  }

  function mockSetNumPendingSlashes(uint16 numPendingSlashes_) public {
    numPendingSlashes = numPendingSlashes_;
  }

  function mockSetPayoutHandlerNumPendingSlashes(address payoutHandler_, uint256 numPendingSlashes_) public {
    payoutHandlerNumPendingSlashes[payoutHandler_] = numPendingSlashes_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) public {
    reservePools.push(reservePool_);
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  // -------- Overridden common abstract functions --------

  function claimRewards(uint16, /* reservePoolId_ */ address /* receiver_ */ ) public view virtual override {
    __readStub__();
  }

  function dripRewards() public view virtual override {
    __readStub__();
  }

  function dripFees() public view override {
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

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /* lastDripTime_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _updateUserRewards(
    uint256, /* userStkTokenBalance_*/
    mapping(uint16 => ClaimableRewardsData) storage, /* claimableRewards_ */
    UserRewardsData[] storage /* userRewards_ */
  ) internal view virtual override {
    __readStub__();
  }

  function _dripRewardPool(RewardPool storage /* rewardPool_ */ ) internal view override {
    __readStub__();
  }

  function _applyPendingDrippedRewards(
    ReservePool storage, /* reservePool_ */
    mapping(uint16 => ClaimableRewardsData) storage /* claimableRewards_ */
  ) internal view override {
    __readStub__();
  }

  function _dripFeesFromReservePool(ReservePool storage, /* reservePool_ */ IDripModel /* dripModel_ */ )
    internal
    view
    override
  {
    __readStub__();
  }

  function _dripAndResetCumulativeRewardsValues(
    ReservePool[] storage, /* reservePools_ */
    RewardPool[] storage /* rewardPools_ */
  ) internal view override {
    __readStub__();
  }
}
