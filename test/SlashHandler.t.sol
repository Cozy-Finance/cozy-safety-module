// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ICozySafetyModuleManager} from "../src/interfaces/ICozySafetyModuleManager.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ISlashHandlerErrors} from "../src/interfaces/ISlashHandlerErrors.sol";
import {ISlashHandlerEvents} from "../src/interfaces/ISlashHandlerEvents.sol";
import {SafetyModuleState, TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {SlashHandler} from "../src/lib/SlashHandler.sol";
import {Redeemer} from "../src/lib/Redeemer.sol";
import {AssetPool, ReservePool} from "../src/lib/structs/Pools.sol";
import {Slash} from "../src/lib/structs/Slash.sol";
import {Trigger} from "../src/lib/structs/Trigger.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract SlashHandlerTest is TestBase {
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
    return MathConstants.WAD - slashAmount_.divWadUp(oldPoolAmount_);
  }

  function _testSingleSlashSuccess(uint128 depositAmount_, uint128 slashAmount_) internal {
    address receiver_ = _randomAddress();
    uint256 pendingWithdrawalsAmount_ = bound(_randomUint256(), 0, depositAmount_);
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: depositAmount_}));
    mockAsset.mint(address(component), depositAmount_);

    component.mockSetQueuedConfigUpdateHash(_randomBytes32());

    Slash[] memory slashes_ = new Slash[](1);
    slashes_[0] = Slash({reservePoolId: 0, amount: slashAmount_});

    if (slashAmount_ > 0) {
      _expectEmit();
      emit IERC20.Transfer(address(component), receiver_, slashAmount_);
      _expectEmit();
      emit ISlashHandlerEvents.Slashed(mockPayoutHandler, receiver_, 0, slashAmount_);
    }
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);

    ReservePool memory reservePool_ = component.getReservePool(0);
    if (slashAmount_ >= depositAmount_) {
      assertEq(reservePool_.depositAmount, 0, "depositAmount");
      assertEq(reservePool_.pendingWithdrawalsAmount, 0, "pendingWithdrawalsAmount");
    } else {
      assertEq(reservePool_.depositAmount, depositAmount_ - slashAmount_, "depositAmount");
      assertEq(
        reservePool_.pendingWithdrawalsAmount,
        pendingWithdrawalsAmount_.mulWadDown(_getScalingFactor(depositAmount_, slashAmount_)),
        "pendingWithdrawalsAmount"
      );
    }
    assertEq(component.assetPools(IERC20(address(mockAsset))), depositAmount_ - slashAmount_);
    assertEq(mockAsset.balanceOf(receiver_), slashAmount_);
    assertEq(component.numPendingSlashes(), 0);
    assertEq(component.payoutHandlerNumPendingSlashes(mockPayoutHandler), 0);
    assertEq(component.safetyModuleState(), SafetyModuleState.ACTIVE);
    // The queued config update hash should be reset when the SafetyModule becomes active from triggered.
    assertEq(component.getQueuedConfigUpdateHash(), bytes32(0));
  }

  function test_slash_entireReservePool() public {
    _testSingleSlashSuccess(30e6, 30e6);
  }

  function test_slash_allDepositsPartialStakes() public {
    _testSingleSlashSuccess(30e6, 25e6);
  }

  function test_slash_partialDepositsNoStakes() public {
    _testSingleSlashSuccess(30e6, 5e6);
  }

  function test_slash_noAssets() public {
    _testSingleSlashSuccess(30e6, 0);
  }

  function test_slash_multipleReservePools() public {
    component.mockSetPayoutHandlerNumPendingSlashes(mockPayoutHandler, 3);
    component.mockSetNumPendingSlashes(6);
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);

    uint128 depositAmount_ = 3000e6;
    uint128 pendingWithdrawalsAmount_ = 150e6;
    uint128 slashAmountA_ = 250e6;
    uint128 slashAmountB_ = 50e6;
    uint128 slashAmountC_ = 0;

    address receiver_ = _randomAddress();
    // Reserve pool 0.
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    // Reserve pool 1.
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    // Reserve pool 2.
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: depositAmount_ * 3}));
    // Mint safety module rewards.
    mockAsset.mint(address(component), 3 * depositAmount_);

    bytes32 queuedConfigUpdateHash_ = _randomBytes32();
    component.mockSetQueuedConfigUpdateHash(queuedConfigUpdateHash_);

    Slash[] memory slashes_ = new Slash[](3);
    slashes_[0] = Slash({reservePoolId: 0, amount: slashAmountA_});
    slashes_[1] = Slash({reservePoolId: 1, amount: slashAmountB_});
    slashes_[2] = Slash({reservePoolId: 2, amount: slashAmountC_});

    // Reserve pool 0 slash events.
    _expectEmit();
    emit IERC20.Transfer(address(component), receiver_, slashAmountA_);

    // Reserve pool 1 slash events. The staked assets are not slashed because the deposit amount is sufficient.
    _expectEmit();
    emit IERC20.Transfer(address(component), receiver_, slashAmountB_);

    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);

    // Reserve pool 0 - all deposited assets and some staked assets are slashed.
    ReservePool memory reservePool_ = component.getReservePool(0);
    assertEq(reservePool_.depositAmount, depositAmount_ - slashAmountA_);
    assertEq(
      reservePool_.pendingWithdrawalsAmount,
      uint256(pendingWithdrawalsAmount_).mulWadDown(_getScalingFactor(depositAmount_, slashAmountA_))
    );

    // Reserve pool 1 - some deposited assets and no staked assets are slashed.
    reservePool_ = component.getReservePool(1);
    assertEq(reservePool_.depositAmount, depositAmount_ - slashAmountB_);
    assertEq(
      reservePool_.pendingWithdrawalsAmount,
      uint256(pendingWithdrawalsAmount_).mulWadDown(_getScalingFactor(depositAmount_, slashAmountB_))
    );

    // Reserve pool 2 - no assets are slashed.
    reservePool_ = component.getReservePool(2);
    assertEq(reservePool_.depositAmount, depositAmount_);
    assertEq(reservePool_.pendingWithdrawalsAmount, pendingWithdrawalsAmount_);

    // Aggregate balance and safety module state.
    assertEq(
      component.assetPools(IERC20(address(mockAsset))),
      (3 * depositAmount_) - (slashAmountA_ + slashAmountB_ + slashAmountC_)
    );
    assertEq(mockAsset.balanceOf(receiver_), slashAmountA_ + slashAmountB_ + slashAmountC_);
    assertEq(component.numPendingSlashes(), 5);
    assertEq(component.payoutHandlerNumPendingSlashes(mockPayoutHandler), 2);
    // Still triggered because there are pending slashes.
    assertEq(component.safetyModuleState(), SafetyModuleState.TRIGGERED);
    // The queued config update hash is not reset because the SafetyModule is still triggered.
    assertEq(component.getQueuedConfigUpdateHash(), queuedConfigUpdateHash_);
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

  function test_slash_revert_insufficientReserveAssetsDueToMaxSlashPercentageParameter() public {
    uint128 depositAmount_ = 300e6;
    uint128 pendingWithdrawalsAmount_ = 150e6;
    uint128 slashAmountA_ = 250e6;
    uint128 slashAmountB_ = 301e6;

    address receiver_ = _randomAddress();
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: 0.49e4,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: (depositAmount_) * 2}));
    // Mint safety module reserve assets.
    mockAsset.mint(address(component), (depositAmount_) * 2);

    Slash[] memory slashes_ = new Slash[](2);
    slashes_[0] = Slash({reservePoolId: 0, amount: slashAmountA_});
    slashes_[1] = Slash({reservePoolId: 1, amount: slashAmountB_});

    uint256 slashPercentage_ = uint256(slashAmountB_).mulDivUp(MathConstants.ZOC, depositAmount_);
    vm.expectRevert(abi.encodeWithSelector(ISlashHandlerErrors.ExceedsMaxSlashPercentage.selector, 1, slashPercentage_));
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);
  }

  function test_slash_revert_alreadySlashed() public {
    uint128 depositAmount_ = 300e6;
    uint128 pendingWithdrawalsAmount_ = 150e6;
    uint128 slashAmount_ = 1e6;

    address receiver_ = _randomAddress();
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: (depositAmount_) * 2}));
    // Mint safety module reserve assets.
    mockAsset.mint(address(component), (depositAmount_) * 2);

    Slash[] memory slashes_ = new Slash[](3);
    slashes_[0] = Slash({reservePoolId: 1, amount: slashAmount_});
    slashes_[1] = Slash({reservePoolId: 0, amount: slashAmount_});
    slashes_[2] = Slash({reservePoolId: 1, amount: slashAmount_});

    vm.expectRevert(abi.encodeWithSelector(ISlashHandlerErrors.AlreadySlashed.selector, 1));
    vm.prank(mockPayoutHandler);
    component.slash(slashes_, receiver_);
  }

  function test_getMaxSlashableReservePoolAmount() public {
    uint256 depositAmountA_ = 1000;
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmountA_,
        pendingWithdrawalsAmount: _randomUint256(),
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    assertEq(component.getMaxSlashableReservePoolAmount(0), 1000);

    uint256 depositAmountB_ = 900_000;
    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(0)),
        depositAmount: depositAmountB_,
        pendingWithdrawalsAmount: _randomUint256(),
        feeAmount: _randomUint256(),
        maxSlashPercentage: MathConstants.ZOC / 4,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    assertEq(component.getMaxSlashableReservePoolAmount(1), 225_000);
  }
}

contract TestableSlashHandler is SlashHandler, Redeemer {
  // -------- Getters --------

  function getReservePool(uint8 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  function getQueuedConfigUpdateHash() external view returns (bytes32) {
    return lastConfigUpdate.queuedConfigUpdateHash;
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

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetQueuedConfigUpdateHash(bytes32 hash_) external {
    lastConfigUpdate.queuedConfigUpdateHash = hash_;
  }

  // -------- Overridden common abstract functions --------

  function dripFees() public view override {
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

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /* lastDripTime_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _dripFeesFromReservePool(ReservePool storage, /* reservePool_ */ IDripModel /* dripModel_ */ )
    internal
    view
    override
  {
    __readStub__();
  }
}
