// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {RewardsHandler} from "../src/lib/RewardsHandler.sol";
import {Staker} from "../src/lib/Staker.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {SafeCastLib} from "../src/lib/SafeCastLib.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {Ownable} from "../src/lib/Ownable.sol";
import {AssetPool, ReservePool, UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData, PreviewClaimableRewardsData, PreviewClaimableRewards} from "../src/lib/structs/Rewards.sol";
import {IdLookup} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockStkToken} from "./utils/MockStkToken.sol";
import {MockManager} from "./utils/MockManager.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

contract RewardsHandlerUnitTest is TestBase {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  MockDripModel mockRewardsDripModel;
  TestableRewardsHandler component = new TestableRewardsHandler();

  uint256 constant DEFAULT_REWARDS_DRIP_RATE = 0.01e18;
  uint256 constant DEFAULT_NUM_RESERVE_POOLS = 2;
  uint256 constant DEFAULT_NUM_REWARD_ASSETS = 3;

  event ClaimedRewards(
    uint16 indexed reservePoolId,
    IERC20 indexed rewardAsset_,
    uint256 amount_,
    address indexed owner_,
    address receiver_
  );

  function setUp() public {
    mockRewardsDripModel = new MockDripModel(DEFAULT_REWARDS_DRIP_RATE);
    component.mockSetLastDripTime(block.timestamp);
  }

  function _setUpUndrippedRewardPools(uint256 numRewardAssets_) internal {
    for (uint256 i = 0; i < numRewardAssets_; i++) {
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 amount_ = _randomUint256() % 500_000_000;
      UndrippedRewardPool memory rewardPool_ = UndrippedRewardPool({
        asset: IERC20(address(mockAsset_)),
        depositToken: IReceiptToken(address(0)),
        dripModel: IDripModel(mockRewardsDripModel),
        amount: amount_
      });
      component.mockAddUndrippedRewardPool(rewardPool_);

      // Mint safety module undripped rewards.
      mockAsset_.mint(address(component), amount_);
      component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: amount_}));
    }
  }

  function _setUpReservePools(uint256 numReservePools_) internal {
    for (uint16 i = 0; i < numReservePools_; i++) {
      IReceiptToken stkToken_ =
        IReceiptToken(address(new MockStkToken("Mock Cozy  stkToken", "cozyStk", 6, ISafetyModule(address(component)))));
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 stakeAmount_ = _randomUint256() % 500_000_000;
      uint256 depositAmount_ = _randomUint256() % 500_000_000;
      ReservePool memory reservePool_ = ReservePool({
        asset: IERC20(address(mockAsset_)),
        stkToken: stkToken_,
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: 0,
        pendingWithdrawalsAmount: 0,
        feeAmount: 0,
        rewardsPoolsWeight: (MathConstants.ZOC / numReservePools_).safeCastTo16(),
        maxSlashPercentage: MathConstants.WAD
      });
      component.mockRegisterStkToken(i, stkToken_);
      component.mockAddReservePool(reservePool_);

      mockAsset_.mint(address(component), stakeAmount_ + depositAmount_);
      component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: stakeAmount_ + depositAmount_}));

      // Mint stkTokens and send to zero address to floor supply.
      stkToken_.mint(address(0), _randomUint256() % 500_000_000);
    }
  }

  function _setUpClaimableRewardIndices(uint256 numReservePools_, uint256 numRewardAssets_) internal {
    for (uint16 i = 0; i < numReservePools_; i++) {
      for (uint16 j = 0; j < numRewardAssets_; j++) {
        component.mockSetClaimableRewardIndex(i, j, _randomUint256() % 500_000_000);
      }
    }
  }

  function _setUpDefault() internal {
    _setUpReservePools(DEFAULT_NUM_RESERVE_POOLS);
    _setUpUndrippedRewardPools(DEFAULT_NUM_REWARD_ASSETS);
    _setUpClaimableRewardIndices(DEFAULT_NUM_RESERVE_POOLS, DEFAULT_NUM_REWARD_ASSETS);
  }

  function _setUpConcrete() internal {
    skip(10);

    // Set-up two reserve pools.
    IReceiptToken stkToken1_ =
      IReceiptToken(address(new MockStkToken("Mock Cozy  stkToken", "cozyStk", 6, ISafetyModule(address(component)))));
    component.mockRegisterStkToken(0, stkToken1_);

    MockERC20 mockAsset1_ = new MockERC20("Mock Asset", "MOCK", 6);
    ReservePool memory reservePool1_ = ReservePool({
      asset: IERC20(address(mockAsset1_)),
      stkToken: stkToken1_,
      depositToken: IReceiptToken(address(0)),
      stakeAmount: 100e6,
      depositAmount: 50e6,
      pendingUnstakesAmount: 0,
      pendingWithdrawalsAmount: 0,
      feeAmount: 0,
      rewardsPoolsWeight: 0.1e4, // 10% weight
      maxSlashPercentage: MathConstants.WAD
    });
    stkToken1_.mint(address(0), 0.1e18);
    component.mockAddReservePool(reservePool1_);
    mockAsset1_.mint(address(component), 150e6);
    component.mockAddAssetPool(IERC20(address(mockAsset1_)), AssetPool({amount: 150e6}));

    IReceiptToken stkToken2_ =
      IReceiptToken(address(new MockStkToken("Mock Cozy  stkToken", "cozyStk", 6, ISafetyModule(address(component)))));
    component.mockRegisterStkToken(1, stkToken2_);

    MockERC20 mockAsset2_ = new MockERC20("Mock Asset", "MOCK", 6);
    ReservePool memory reservePool2_ = ReservePool({
      asset: IERC20(address(mockAsset2_)),
      stkToken: stkToken2_,
      depositToken: IReceiptToken(address(0)),
      stakeAmount: 200e6,
      depositAmount: 20e6,
      pendingUnstakesAmount: 0,
      pendingWithdrawalsAmount: 0,
      feeAmount: 0,
      rewardsPoolsWeight: 0.9e4, // 90% weight,
      maxSlashPercentage: MathConstants.WAD
    });
    stkToken2_.mint(address(0), 10);
    component.mockAddReservePool(reservePool2_);
    mockAsset2_.mint(address(component), 220e6);
    component.mockAddAssetPool(IERC20(address(mockAsset2_)), AssetPool({amount: 220e6}));

    // Set-up three undripped reward pools.
    {
      UndrippedRewardPool memory testPool1_;
      MockERC20 asset1_ = new MockERC20("Mock Cozy Reward Token", "rewardToken1", 18);
      IDripModel dripModel1_ = IDripModel(new MockDripModel(0.01e18)); // 1% drip rate

      testPool1_.asset = IERC20(address(asset1_));
      testPool1_.dripModel = dripModel1_;
      testPool1_.amount = 100_000;
      component.mockAddUndrippedRewardPool(testPool1_);
      component.mockAddAssetPool(IERC20(address(asset1_)), AssetPool({amount: testPool1_.amount}));
      asset1_.mint(address(component), testPool1_.amount);
    }
    {
      UndrippedRewardPool memory testPool2_;
      MockERC20 asset2_ = new MockERC20("Mock Cozy Reward Token", "rewardToken1", 18);
      IDripModel dripModel2_ = IDripModel(new MockDripModel(0.25e18)); // 25% drip rate

      testPool2_.asset = IERC20(address(asset2_));
      testPool2_.dripModel = dripModel2_;
      testPool2_.amount = 1_000_000_000;
      component.mockAddUndrippedRewardPool(testPool2_);
      component.mockAddAssetPool(IERC20(address(asset2_)), AssetPool({amount: testPool2_.amount}));
      asset2_.mint(address(component), testPool2_.amount);
    }
    {
      UndrippedRewardPool memory testPool3_;
      MockERC20 asset3_ = new MockERC20("Mock Cozy Reward Token", "rewardToken1", 18);
      IDripModel dripModel3_ = IDripModel(new MockDripModel(1e18)); // 100% drip rate

      testPool3_.asset = IERC20(address(asset3_));
      testPool3_.dripModel = dripModel3_;
      testPool3_.amount = 9999;
      component.mockAddUndrippedRewardPool(testPool3_);
      component.mockAddAssetPool(IERC20(address(asset3_)), AssetPool({amount: testPool3_.amount}));
      asset3_.mint(address(component), testPool3_.amount);
    }
  }

  function _getUserClaimRewardsFixture() internal returns (address user_, uint16 reservePoolId_, address receiver_) {
    user_ = _randomAddress();
    reservePoolId_ = _randomUint16() % uint16(component.getReservePools().length);
    uint256 reserveAssetAmount_ = _randomUint256() % 500_000_000;
    receiver_ = _randomAddress();

    // Mint user reserve assets.
    ReservePool memory reservePool_ = component.getReservePool(reservePoolId_);
    MockERC20 mockAsset_ = MockERC20(address(reservePool_.asset));
    mockAsset_.mint(user_, reserveAssetAmount_);

    vm.prank(user_);
    mockAsset_.approve(address(component), type(uint256).max);
    component.stake(reservePoolId_, reserveAssetAmount_, user_, user_);
    vm.stopPrank();
  }

  function _calculateExpectedDripQuantity(uint256 poolAmount_, uint256 dripFactor_) internal pure returns (uint256) {
    return poolAmount_.mulWadDown(dripFactor_);
  }

  function _calculateExpectedUpdateToClaimableRewardIndex(
    uint256 totalDrippedRewards_,
    uint256 rewardsPoolsWeight_,
    uint256 stkTokenSupply_
  ) internal pure returns (uint256) {
    uint256 scaledDrippedRewards_ = totalDrippedRewards_.mulDivDown(rewardsPoolsWeight_, MathConstants.ZOC);
    return scaledDrippedRewards_.divWadDown(stkTokenSupply_);
  }
}

contract RewardsHandlerDripUnitTest is RewardsHandlerUnitTest {
  using SafeCastLib for uint256;

  function testFuzz_noDripIfSafetyModuleIsPaused(uint64 timeElapsed_) public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    timeElapsed_ = uint64(bound(timeElapsed_, 0, type(uint64).max - component.getLastDripTime()));
    skip(timeElapsed_);

    UndrippedRewardPool[] memory initialUndrippedRewardPools_ = component.getUndrippedRewardPools();
    uint256[][] memory initialClaimableRewardIndices_ = component.getClaimableRewardIndices();

    component.dripRewards();
    assertEq(component.getUndrippedRewardPools(), initialUndrippedRewardPools_);
    assertEq(component.getClaimableRewardIndices(), initialClaimableRewardIndices_);
  }

  function test_noDripIfNoTimeElapsed() public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    UndrippedRewardPool[] memory initialUndrippedRewardPools_ = component.getUndrippedRewardPools();
    uint256[][] memory initialClaimableRewardIndices_ = component.getClaimableRewardIndices();

    component.dripRewards();
    assertEq(component.getUndrippedRewardPools(), initialUndrippedRewardPools_);
    assertEq(component.getClaimableRewardIndices(), initialClaimableRewardIndices_);
  }

  function test_rewardsDripConcrete() public {
    _setUpConcrete();

    UndrippedRewardPool[] memory expectedUndrippedRewardPools_ = new UndrippedRewardPool[](3);
    UndrippedRewardPool[] memory concreteUndrippedRewardPools_ = component.getUndrippedRewardPools();
    {
      UndrippedRewardPool memory expectedPool1_;
      expectedPool1_.asset = concreteUndrippedRewardPools_[0].asset;
      expectedPool1_.dripModel = concreteUndrippedRewardPools_[0].dripModel;
      expectedPool1_.amount = 99_000; // (1 - dripRate) * originalUndrippedPoolAmount = (1.0 - 0.01) * 100_000
      expectedUndrippedRewardPools_[0] = expectedPool1_;
    }
    {
      UndrippedRewardPool memory expectedPool2_;
      expectedPool2_.asset = concreteUndrippedRewardPools_[1].asset;
      expectedPool2_.dripModel = concreteUndrippedRewardPools_[1].dripModel;
      expectedPool2_.amount = 750_000_000; // (1 - dripRate) * originalUndrippedPoolAmount = (1.0 - 0.25) *
        // 1_000_000_000
      expectedUndrippedRewardPools_[1] = expectedPool2_;
    }
    {
      UndrippedRewardPool memory expectedPool3_;
      expectedPool3_.asset = concreteUndrippedRewardPools_[2].asset;
      expectedPool3_.dripModel = concreteUndrippedRewardPools_[2].dripModel;
      expectedPool3_.amount = 0; // (1 - dripRate) * originalUndrippedPoolAmount = (1.0 - 1.0) * 9999
      expectedUndrippedRewardPools_[2] = expectedPool3_;
    }

    // Set-up claimable reward indices.
    uint256[][] memory expectedClaimableRewardsIndices_ = component.getClaimableRewardIndices();
    {
      expectedClaimableRewardsIndices_[0][0] = 1000; // [(drippedRewards * rewardsPoolWeight) / stkTokenSupply] * WAD =
        // [(1000 * 0.1) / 0.1e18] * WAD
      expectedClaimableRewardsIndices_[0][1] = 250_000_000; // [(250_000_000 * 0.1) / 0.1e18] * WAD
      expectedClaimableRewardsIndices_[0][2] = 9990; //  [(9999 * 0.1) / 0.1e18] * WAD

      expectedClaimableRewardsIndices_[1][0] = 900e17; // [(1000 * 0.9) / 10] * WAD
      expectedClaimableRewardsIndices_[1][1] = 225_000_000e17; // [(250_000_000 * 0.9) / 10] * WAD
      expectedClaimableRewardsIndices_[1][2] = 8999e17; // [(9999 * 0.9) / 10] * WAD
    }

    component.dripRewards();
    assertEq(component.getUndrippedRewardPools(), expectedUndrippedRewardPools_);
    assertEq(component.getClaimableRewardIndices(), expectedClaimableRewardsIndices_);
    assertEq(component.getLastDripTime(), block.timestamp);
  }

  function testFuzz_rewardsDrip(uint64 timeElapsed_) public {
    _setUpDefault();

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    timeElapsed_ = uint64(bound(timeElapsed_, 1, type(uint64).max - component.getLastDripTime()));
    skip(timeElapsed_);

    UndrippedRewardPool[] memory expectedUndrippedRewardPools_ = component.getUndrippedRewardPools();
    uint256[][] memory expectedClaimableRewardsIndices_ = component.getClaimableRewardIndices();

    uint256 numRewardAssets_ = expectedUndrippedRewardPools_.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      UndrippedRewardPool memory setUpUndrippedRewardPool_ = copyUndrippedRewardPool(expectedUndrippedRewardPools_[i]);
      uint256 expectedDripRate_ = _randomUint256() % MathConstants.WAD;
      MockDripModel model_ = new MockDripModel(expectedDripRate_);
      setUpUndrippedRewardPool_.dripModel = model_;

      // Update market with model that has a new drip rate.
      component.mockSetUndrippedRewardPool(i, setUpUndrippedRewardPool_);

      // Set up test cases.
      UndrippedRewardPool memory expectedUndrippedRewardPool_ = expectedUndrippedRewardPools_[i];
      expectedUndrippedRewardPool_.dripModel = model_;
      uint256 totalDrippedAssets_ =
        _calculateExpectedDripQuantity(expectedUndrippedRewardPool_.amount, expectedDripRate_);
      expectedUndrippedRewardPool_.amount -= totalDrippedAssets_;
      expectedUndrippedRewardPools_[i] = expectedUndrippedRewardPool_;

      uint256 numReservePools_ = expectedClaimableRewardsIndices_.length;
      for (uint16 j = 0; j < numReservePools_; j++) {
        ReservePool memory reservePool_ = component.getReservePool(j);
        expectedClaimableRewardsIndices_[j][i] = component.getClaimableRewardIndex(j, i)
          + _calculateExpectedUpdateToClaimableRewardIndex(
            totalDrippedAssets_, reservePool_.rewardsPoolsWeight, reservePool_.stkToken.totalSupply()
          );
      }
    }

    component.dripRewards();
    assertEq(component.getUndrippedRewardPools(), expectedUndrippedRewardPools_);
    assertEq(component.getClaimableRewardIndices(), expectedClaimableRewardsIndices_);
    assertEq(component.getLastDripTime(), block.timestamp);
  }

  function test_revertOnInvalidDripFactor() public {
    _setUpDefault();

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    skip(99);

    uint256 dripRate_ = MathConstants.WAD + 1;
    MockDripModel model_ = new MockDripModel(dripRate_);
    // Update a random pool to an invalid drip model.
    uint16 poolId_ = _randomUint16() % uint16(component.getUndrippedRewardPools().length);
    UndrippedRewardPool memory undrippedRewardPool_ = copyUndrippedRewardPool(component.getUndrippedRewardPool(poolId_));
    undrippedRewardPool_.dripModel = model_;
    component.mockSetUndrippedRewardPool(poolId_, undrippedRewardPool_);

    vm.expectRevert(ICommonErrors.InvalidDripFactor.selector);
    component.dripRewards();
  }
}

contract RewardsHandlerClaimUnitTest is RewardsHandlerUnitTest {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  function test_claimRewardsConcrete() public {
    _setUpConcrete();

    // Drip rewards once and skip some time, so it will drip again on the next rewards claim.
    component.dripRewards();
    skip(1000);

    // Get reserve pools and undripped reward pools.
    ReservePool[] memory reservePools_ = component.getReservePools();
    MockERC20 reserveAsset1_ = MockERC20(address(reservePools_[0].asset));
    MockERC20 reserveAsset2_ = MockERC20(address(reservePools_[1].asset));
    UndrippedRewardPool[] memory undrippedRewardPools_ = component.getUndrippedRewardPools();

    // Set-up two stakers with reserve assets.
    address user1 = _randomAddress();
    address user2 = _randomAddress();
    reserveAsset1_.mint(user1, type(uint128).max);
    reserveAsset1_.mint(user2, type(uint128).max);
    reserveAsset2_.mint(user1, type(uint128).max);
    reserveAsset2_.mint(user2, type(uint128).max);

    vm.startPrank(user1);
    reserveAsset1_.approve(address(component), type(uint256).max);
    reserveAsset2_.approve(address(component), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(user2);
    reserveAsset1_.approve(address(component), type(uint256).max);
    reserveAsset2_.approve(address(component), type(uint256).max);
    vm.stopPrank();

    // User 1 stakes 100e6 in pool1, increasing stkTokenSupply to 0.2e18. User 1 owns 50% of total stake, 200e6.
    vm.prank(user1);
    component.stake(0, 100e6, user1, user1);
    // User 2 stakes 800e6 in pool2, increasing stkTokenSupply to 50. User 2 owns 80% of total stake, 1000e6.
    vm.prank(user2);
    component.stake(1, 800e6, user2, user2);

    skip(1000);

    {
      address receiver_ = _randomAddress();
      _expectEmit();
      emit ClaimedRewards(0, undrippedRewardPools_[0].asset, 49, user1, receiver_);
      _expectEmit();
      emit ClaimedRewards(0, undrippedRewardPools_[1].asset, 9_375_000, user1, receiver_);

      vm.startPrank(user1);
      // User 1 should be transferred 50% of all rewards dripped.
      component.claimRewards(0, receiver_);
      vm.stopPrank();

      // Reward amounts received by `receiver_` are calculated as: undrippedRewardPool.amount * dripRate *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
      assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(receiver_), 49, 1); // 99_000 * 0.01 * 0.1 * 0.5
      assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(receiver_), 9_375_000, 1); // 750_000_000 * 0.25 * 0.1
        // * 0.5
      assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(receiver_), 0, 1); // 0 * 1.0 * 0.1 * 0.5

      // Since user claimed rewards, accrued rewards should be 0 and index snapshot should be updated.
      UserRewardsData[] memory user1RewardsData_ = component.getUserRewards(0, user1);
      UserRewardsData[] memory expectedUser1RewardsData_ = new UserRewardsData[](3);
      expectedUser1RewardsData_[0] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 0).safeCastTo128()});
      expectedUser1RewardsData_[1] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 1).safeCastTo128()});
      expectedUser1RewardsData_[2] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 2).safeCastTo128()});
      assertEq(user1RewardsData_, expectedUser1RewardsData_);

      // Undripped reward pools should be updated as: undrippedRewardPool.amount * (1 - dripRate).
      UndrippedRewardPool[] memory undrippedRewardPoolsUpdated_ = component.getUndrippedRewardPools();
      assertEq(undrippedRewardPoolsUpdated_[0].amount, 98_010); // 99_000 * (1 - 0.01)
      assertEq(undrippedRewardPoolsUpdated_[1].amount, 562_500_000); // 750_000_000 * (1 - 0.25)
      assertEq(undrippedRewardPoolsUpdated_[2].amount, 0); // 0 * (1 - 1.0)

      // Claimable reward indices should be updated as: oldIndex + [(drippedRewards * rewardsPoolWeight) /
      // stkTokenSupply] * WAD.
      uint256[][] memory claimableRewardIndices_ = component.getClaimableRewardIndices();
      assertEq(claimableRewardIndices_[0][0], 1495); // 1000 + [(990 * 0.1) / 0.2e18] * WAD
      assertEq(claimableRewardIndices_[0][1], 343_750_000); // 250_000_000 + [(187_500_000 * 0.1) / 0.2e18] * WAD
      assertEq(claimableRewardIndices_[0][2], 9990); // 9_990 + [(0 * 0.1) / 0.2e18] * WAD
      assertEq(claimableRewardIndices_[1][0], 107_820_000_000_000_000_000); // 900e17 + [(990 * 0.9) / 50] * WAD
      assertEq(claimableRewardIndices_[1][1], 25_875_000_000_000_000_000_000_000); // 225_000_000e17 + [(187_500_000 *
        // 0.9) / 50] * WAD
      assertEq(claimableRewardIndices_[1][2], 8999e17); // 8999e17 + [(0 * 0.9) / 50] * WAD
    }

    skip(10);

    vm.prank(user2);
    component.stake(0, 200e6, user2, user2); // Owns 50% of total stake, 400e6

    {
      address receiver_ = _randomAddress();
      _expectEmit();
      emit ClaimedRewards(0, undrippedRewardPools_[0].asset, 24, user1, receiver_);
      _expectEmit();
      emit ClaimedRewards(0, undrippedRewardPools_[1].asset, 3_515_625, user1, receiver_);

      vm.startPrank(user1);
      // Receiver should be transferred 25% of all rewards dripped.
      component.claimRewards(0, receiver_);
      vm.stopPrank();

      // Reward amounts received by `receiver_` are calculated as: undrippedRewardPool.amount * dripRate *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
      assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(receiver_), 24, 1); // 98_010 * 0.01 * 0.1 * 0.25
      assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(receiver_), 3_515_625, 1); // 562_500_000 * 0.25 * 0.1
        // * 0.25
      assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(receiver_), 0, 1); // 0 * 1.0 * 0.1 * 0.25
    }

    {
      address receiver1_ = _randomAddress();
      _expectEmit();
      emit ClaimedRewards(0, undrippedRewardPools_[0].asset, 49, user2, receiver1_);
      _expectEmit();
      emit ClaimedRewards(0, undrippedRewardPools_[1].asset, 7_031_250, user2, receiver1_);

      vm.startPrank(user2);
      component.claimRewards(0, receiver1_);
      vm.stopPrank();

      address receiver2_ = _randomAddress();
      _expectEmit();
      emit ClaimedRewards(1, undrippedRewardPools_[0].asset, 1418, user2, receiver2_);
      _expectEmit();
      emit ClaimedRewards(1, undrippedRewardPools_[1].asset, 236_250_000, user2, receiver2_);

      vm.startPrank(user2);
      component.claimRewards(1, receiver2_);
      vm.stopPrank();

      // Reward amounts received by `receiver_` are calculated as: undrippedRewardPool.amount * dripRate *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
      assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(receiver1_), 49, 1); // 98_010 * 0.01 * 0.1 * 0.5
      assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(receiver1_), 7_031_250, 1); // 562_500_000 * 0.25 * 0.1
        // * 0.5
      assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(receiver1_), 0, 1); // 0 * 1.0 * 0.1 * 0.5

      // Rewards have dripped twice since user 2 claimed rewards from pool1, so rewards amounts received by `receiver_`
      // are calculated as: (firstTimeUndrippedRewardPool1.amount + secondTimeUndrippedRewardPool1.amount) * dripRate *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
      assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(receiver2_), 1418, 1); // (99_000 + 98_010) * 0.01 *
        // 0.9 * 0.8
      assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(receiver2_), 236_250_000, 1); // (750_000_000 +
        // 562_500_000) * 0.25 * 0.9 * 0.8
      assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(receiver2_), 0, 1); // (0 + 0) * 1.0 * 0.9 * 0.8

      // Since user claimed full rewards, user's accrued rewards should be 0 and index snapshot should be updated.
      UserRewardsData[] memory user2RewardsData1_ = component.getUserRewards(0, user2);
      UserRewardsData[] memory expectedUser2RewardsData1_ = new UserRewardsData[](3);
      expectedUser2RewardsData1_[0] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 0).safeCastTo128()});
      expectedUser2RewardsData1_[1] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 1).safeCastTo128()});
      expectedUser2RewardsData1_[2] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 2).safeCastTo128()});
      assertEq(user2RewardsData1_, expectedUser2RewardsData1_);

      UserRewardsData[] memory user2RewardsData2_ = component.getUserRewards(1, user2);
      UserRewardsData[] memory expectedUser2RewardsData2_ = new UserRewardsData[](3);
      expectedUser2RewardsData2_[0] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(1, 0).safeCastTo128()});
      expectedUser2RewardsData2_[1] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(1, 1).safeCastTo128()});
      expectedUser2RewardsData2_[2] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(1, 2).safeCastTo128()});
      assertEq(user2RewardsData2_, expectedUser2RewardsData2_);
    }
  }

  function testFuzz_previewClaimableRewards(uint64 timeElapsed_) public {
    _setUpDefault();

    (address user_, uint16 reservePoolId_, address receiver_) = _getUserClaimRewardsFixture();
    vm.assume(reservePoolId_ != 0);

    // Compute original number of reward pools.
    uint256 oldNumRewardPools_ = component.getUndrippedRewardPools().length;

    // Add new reward asset pool.
    {
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 newRewardPoolAmount_ = _randomUint256() % 500_000_000;
      UndrippedRewardPool memory rewardPool_ = UndrippedRewardPool({
        asset: IERC20(address(mockAsset_)),
        depositToken: IReceiptToken(address(0)),
        dripModel: IDripModel(mockRewardsDripModel),
        amount: newRewardPoolAmount_
      });
      component.mockAddUndrippedRewardPool(rewardPool_);
      // Mint safety module undripped rewards.
      mockAsset_.mint(address(component), newRewardPoolAmount_);
      component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: newRewardPoolAmount_}));
    }

    skip(timeElapsed_);

    // User previews rewards and then claims rewards (rewards drip in the claim).
    vm.startPrank(user_);
    // User previews two pools, reservePoolId_ (the pool they staked into) and 0 (the pool they did not stake into).
    uint16[] memory previewReservePoolIds_ = new uint16[](2);
    previewReservePoolIds_[0] = reservePoolId_;
    previewReservePoolIds_[1] = 0;
    PreviewClaimableRewards[] memory previewClaimableRewards_ =
      component.previewClaimableRewards(previewReservePoolIds_, user_);
    component.claimRewards(reservePoolId_, receiver_);
    vm.stopPrank();

    // Check preview claimable rewards.
    PreviewClaimableRewards[] memory expectedPreviewClaimableRewards_ = new PreviewClaimableRewards[](2);
    UndrippedRewardPool[] memory undrippedRewardPools_ = component.getUndrippedRewardPools();
    PreviewClaimableRewardsData[] memory expectedPreviewClaimableRewardsData_ =
      new PreviewClaimableRewardsData[](undrippedRewardPools_.length);
    PreviewClaimableRewardsData[] memory expectedPreviewClaimableRewardsDataPool0_ =
      new PreviewClaimableRewardsData[](undrippedRewardPools_.length);
    for (uint16 i = 0; i < undrippedRewardPools_.length; i++) {
      IERC20 asset_ = undrippedRewardPools_[i].asset;
      expectedPreviewClaimableRewardsData_[i] =
        PreviewClaimableRewardsData({rewardPoolId: i, amount: asset_.balanceOf(receiver_), asset: asset_});
      expectedPreviewClaimableRewardsDataPool0_[i] =
        PreviewClaimableRewardsData({rewardPoolId: i, amount: 0, asset: asset_});
    }
    expectedPreviewClaimableRewards_[0] = PreviewClaimableRewards({
      reservePoolId: reservePoolId_,
      claimableRewardsData: expectedPreviewClaimableRewardsData_
    });
    expectedPreviewClaimableRewards_[1] =
      PreviewClaimableRewards({reservePoolId: 0, claimableRewardsData: expectedPreviewClaimableRewardsDataPool0_});

    assertEq(previewClaimableRewards_, expectedPreviewClaimableRewards_);
    assertEq(previewClaimableRewards_[0].claimableRewardsData.length, oldNumRewardPools_ + 1);
  }

  function testFuzz_claimRewards(uint64 timeElapsed_) public {
    _setUpDefault();

    (address user_, uint16 reservePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    skip(timeElapsed_);
    uint256 userStkTokenBalance_ = component.getReservePool(reservePoolId_).stkToken.balanceOf(user_);
    uint256[] memory oldClaimableRewardIndices_ = component.getClaimableRewardIndices(reservePoolId_);

    // User claims rewards.
    vm.prank(user_);
    component.claimRewards(reservePoolId_, receiver_);

    // Check receiver balances and user rewards data.
    uint256[] memory newClaimableRewardIndices_ = component.getClaimableRewardIndices(reservePoolId_);
    UserRewardsData[] memory newUserRewards_ = component.getUserRewards(reservePoolId_, user_);
    UndrippedRewardPool[] memory undrippedRewardPools_ = component.getUndrippedRewardPools();
    for (uint16 i = 0; i < undrippedRewardPools_.length; i++) {
      IERC20 asset_ = undrippedRewardPools_[i].asset;
      uint256 accruedRewards_ = component.getUserAccruedRewards(
        userStkTokenBalance_, newClaimableRewardIndices_[i], oldClaimableRewardIndices_[i]
      );
      assertApproxEqAbs(asset_.balanceOf(receiver_), accruedRewards_, 1);
      assertApproxEqAbs(newUserRewards_[i].indexSnapshot, newClaimableRewardIndices_[i], 1);
      assertEq(newUserRewards_[i].accruedRewards, 0);
    }
  }

  function test_claimRewardsWithNewRewardAssets() public {
    _test_claimRewardsWithNewRewardAssets(DEFAULT_NUM_REWARD_ASSETS);
  }

  function test_claimRewardsWithZeroInitialRewardAssets() public {
    _test_claimRewardsWithNewRewardAssets(0);
  }

  function _test_claimRewardsWithNewRewardAssets(uint256 numRewardsPools_) public {
    _setUpReservePools(DEFAULT_NUM_RESERVE_POOLS);
    _setUpUndrippedRewardPools(numRewardsPools_);
    _setUpClaimableRewardIndices(DEFAULT_NUM_RESERVE_POOLS, numRewardsPools_);

    (address user_, uint16 reservePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    // Add new reward asset pool.
    MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
    {
      uint256 amount_ = 9000;
      UndrippedRewardPool memory rewardPool_ = UndrippedRewardPool({
        asset: IERC20(address(mockAsset_)),
        depositToken: IReceiptToken(address(0)),
        dripModel: IDripModel(mockRewardsDripModel),
        amount: amount_
      });
      component.mockAddUndrippedRewardPool(rewardPool_);
      mockAsset_.mint(address(component), amount_);
      component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: amount_}));
    }

    ReservePool memory reservePool_ = component.getReservePool(reservePoolId_);
    uint256 userStkTokenBalance_ = reservePool_.stkToken.balanceOf(user_);

    skip(100);
    vm.prank(user_);
    component.claimRewards(reservePoolId_, receiver_);

    // Make sure receiver received rewards from new reward asset pool.
    uint256 userShare_ = userStkTokenBalance_.divWadDown(reservePool_.stkToken.totalSupply());
    uint256 totalDrippedRewards_ = 90;
    uint256 drippedRewards_ = totalDrippedRewards_.mulDivDown(reservePool_.rewardsPoolsWeight, MathConstants.ZOC); // 9000
      // * 0.1 *
      // rewardsPoolWeight
    assertApproxEqAbs(mockAsset_.balanceOf(receiver_), drippedRewards_.mulWadDown(userShare_), 1);

    // Make sure user rewards data reflects new reward asset pool.
    UserRewardsData[] memory userRewardsData_ = component.getUserRewards(reservePoolId_, user_);
    assertEq(userRewardsData_[numRewardsPools_].accruedRewards, 0);
    assertEq(
      userRewardsData_[numRewardsPools_].indexSnapshot,
      component.getClaimableRewardIndex(reservePoolId_, uint16(numRewardsPools_))
    );
  }

  function test_claimRewardsTwice() public {
    _setUpDefault();
    (address user_, uint16 reservePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    skip(10);

    // User claims rewards.
    vm.startPrank(user_);
    component.claimRewards(reservePoolId_, receiver_);
    UserRewardsData[] memory oldUserRewardsData_ = component.getUserRewards(reservePoolId_, user_);
    vm.stopPrank();

    // User claims rewards again.
    address newReceiver_ = _randomAddress();
    vm.startPrank(user_);
    component.claimRewards(reservePoolId_, newReceiver_);
    UserRewardsData[] memory newUserRewardsData_ = component.getUserRewards(reservePoolId_, user_);
    vm.stopPrank();

    // User rewards data is unchanged.
    assertEq(oldUserRewardsData_, newUserRewardsData_);
    // New receiver receives no reward assets.
    UndrippedRewardPool[] memory undrippedRewardPools_ = component.getUndrippedRewardPools();
    for (uint16 i = 0; i < undrippedRewardPools_.length; i++) {
      assertEq(undrippedRewardPools_[i].asset.balanceOf(newReceiver_), 0);
    }
  }

  function test_claimRewardsAfterTwoIndependentStakes() public {
    _setUpConcrete();

    address user_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint user reserve assets.
    ReservePool[] memory reservePools_ = component.getReservePools();
    MockERC20 reserveAsset1_ = MockERC20(address(reservePools_[0].asset));
    reserveAsset1_.mint(user_, type(uint128).max);

    // User stakes 100e6, increasing stkTokenSupply to 0.2e18. User owns 50% of total stake, 200e6.
    vm.startPrank(user_);
    reserveAsset1_.approve(address(component), type(uint256).max);
    uint256 originalUserStkTokenAmount_ = component.stake(0, 100e6, user_, user_);
    vm.stopPrank();

    // Drip rewards the first time.
    skip(10);
    component.dripRewards();

    // User transfers all stkTokens to receiver.
    IERC20 stkToken_ = component.getReservePool(0).stkToken;
    vm.startPrank(user_);
    stkToken_.transfer(receiver_, originalUserStkTokenAmount_);
    vm.stopPrank();

    // Time passes, user stakes again and rewards drip the second time. Again, user owns 50% of the new total stake,
    // 400e6.
    skip(10);
    vm.startPrank(user_);
    component.stake(0, 200e6, user_, user_);
    vm.stopPrank();
    component.dripRewards();

    // Both users claim rewards.
    vm.prank(user_);
    component.claimRewards(0, user_);
    vm.prank(receiver_);
    component.claimRewards(0, receiver_);

    // Check rewards balances.
    UndrippedRewardPool[] memory undrippedRewardPools_ = component.getUndrippedRewardPools();

    // The user receives rewards from the first rewards drip, from their original stkTokens. Then, they transfer the
    // original stkTokens to receiver and stake again. They receive rewards on the second rewards drip, from their new
    // stkTokens. At each point in time, they are holding 50% of the stkTokenSupply.
    // firstStakeRewards = 100_000 * 0.01 * 0.1 * 0.5 = 50
    // secondStakeRewards = 99_000 * 0.01 * 0.1 * 0.5 = 49
    assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(user_), 99, 1);
    // firstStakeRewards = 1_000_000_000 * 0.25 * 0.1 * 0.5 = 12_500_000
    // secondStakeRewards = 750_000_000 * 0.25 * 0.1 * 0.5 = 9_375_000
    assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(user_), 21_875_000, 1);
    // firstStakeRewards = 9_999 * 1.0 * 0.1 * 0.5 = 499
    // secondStakeRewards = 0 * 1.0 * 0.1 * 0.5 = 0
    assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(user_), 499, 1);

    // The receiver only receives rewards from the second rewards drip, after they have been transferred stkTokens. They
    // hold 25% of the stkToken supply.
    // secondStakeRewards = 99_000 * 0.01 * 0.1 * 0.25 = 24
    assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(receiver_), 24, 1);
    // secondStakeRewards = 750_000_000 * 0.25 * 0.1 * 0.25 = 4_687_500
    assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(receiver_), 4_687_500, 1);
    // secondStakeRewards = 0 * 1.0 * 0.1 * 0.25 = 0
    assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(receiver_), 0, 1);
  }
}

contract RewardsHandlerStkTokenTransferUnitTest is RewardsHandlerUnitTest {
  using SafeCastLib for uint256;

  function test_stkTokenTransferRewardsAccounting() public {
    _test_stkTokenTransferFuncRewardsAccounting(false);
  }

  function test_stkTokenTransferFromRewardsAccounting() public {
    _test_stkTokenTransferFuncRewardsAccounting(true);
  }

  function _test_stkTokenTransferFuncRewardsAccounting(bool useTransferFrom) internal {
    _setUpConcrete();
    address user_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint user reserve assets for pool1.
    ReservePool memory reservePool_ = component.getReservePool(0);
    MockERC20 mockAsset_ = MockERC20(address(reservePool_.asset));
    mockAsset_.mint(user_, type(uint128).max);

    // User stakes 100e6 to pool1.
    vm.startPrank(user_);
    mockAsset_.approve(address(component), type(uint256).max);
    uint256 userStkTokenBalance_ = component.stake(0, 100e6, user_, user_); // Owns 50% of total stake, 200e6
    vm.stopPrank();

    // User transfers 25% the stkTokens.
    if (!useTransferFrom) {
      vm.prank(user_);
      reservePool_.stkToken.transfer(receiver_, userStkTokenBalance_ / 4);
    } else {
      address approvedAddress_ = _randomAddress();
      vm.prank(user_);
      reservePool_.stkToken.approve(approvedAddress_, type(uint256).max);

      vm.prank(approvedAddress_);
      reservePool_.stkToken.transferFrom(user_, receiver_, userStkTokenBalance_ / 4);
    }

    // Check stkToken balances.
    uint256 receiverStkTokenBalance_ = userStkTokenBalance_ / 4;
    assertEq(reservePool_.stkToken.balanceOf(user_), userStkTokenBalance_ - receiverStkTokenBalance_);
    assertEq(reservePool_.stkToken.balanceOf(receiver_), receiverStkTokenBalance_);

    vm.startPrank(user_);
    // User claims rewards.
    component.claimRewards(0, user_);
    vm.stopPrank();

    // Check user rewards balances.
    UndrippedRewardPool[] memory undrippedRewardPools_ = component.getUndrippedRewardPools();

    // Reward amounts received by `user_` are calculated as: undrippedRewardPool.amount * dripRate *
    // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
    assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(user_), 37, 1); // 100_000 * 0.01 * 0.1 * (0.5 * 0.75)
    assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(user_), 9_375_000, 1); // 1_000_000_000 * 0.25 * 0.1 *
      // (0.5 * 0.75)
    assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(user_), 375, 1); // 9_999 * 1.0 * 0.1 * (0.5 * 0.75)

    // Check user rewards data.
    UserRewardsData[] memory userRewardsData_ = component.getUserRewards(0, user_);
    UserRewardsData[] memory expectedUserRewardsData_ = new UserRewardsData[](3);
    expectedUserRewardsData_[0] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 0).safeCastTo128()});
    expectedUserRewardsData_[1] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 1).safeCastTo128()});
    expectedUserRewardsData_[2] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 2).safeCastTo128()});
    assertEq(userRewardsData_, expectedUserRewardsData_);

    skip(100); // Will induce another drip of rewards
    vm.startPrank(receiver_);
    // Receiver claims rewards.
    component.claimRewards(0, receiver_);
    vm.stopPrank();

    // Check user rewards balances.
    assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(receiver_), 24, 1); // (100_000 + 99_000) * 0.01 * 0.1 *
      // (0.5 * 0.25)
    assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(receiver_), 5_468_750, 1); // (1_000_000_000 +
      // 750_000_000) * 0.25 * 0.1 * (0.5 * 0.25)
    assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(receiver_), 124, 1); // (9_999 + 0) * 1.0 * 0.1 * (0.5 *
      // 0.25)

    // Check user rewards data.
    UserRewardsData[] memory receiverRewardsData_ = component.getUserRewards(0, receiver_);
    UserRewardsData[] memory expectedReceiverRewardsData_ = new UserRewardsData[](3);
    expectedReceiverRewardsData_[0] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 0).safeCastTo128()});
    expectedReceiverRewardsData_[1] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 1).safeCastTo128()});
    expectedReceiverRewardsData_[2] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardIndex(0, 2).safeCastTo128()});
    assertEq(receiverRewardsData_, expectedReceiverRewardsData_);
  }

  function test_multipleStkTokenTransfersRewardsAccounting() public {
    _setUpConcrete();
    address user_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint user reserve assets for pool1.
    ReservePool memory reservePool_ = component.getReservePool(0);
    MockERC20 mockAsset_ = MockERC20(address(reservePool_.asset));
    mockAsset_.mint(user_, type(uint128).max);

    // User stakes 100e6 to pool1.
    vm.startPrank(user_);
    mockAsset_.approve(address(component), type(uint256).max);
    uint256 userStkTokenBalance_ = component.stake(0, 100e6, user_, user_); // Owns 50% of total stake, 200e6
    vm.stopPrank();

    // User transfers the stkTokens to receiver.
    vm.prank(user_);
    reservePool_.stkToken.transfer(receiver_, userStkTokenBalance_);

    // Time passes, but no rewards drip.
    skip(100);

    // Receiver transfers the stkTokens back to user.
    vm.prank(receiver_);
    reservePool_.stkToken.transfer(user_, userStkTokenBalance_);

    vm.startPrank(user_);
    // User claims rewards.
    component.claimRewards(0, user_);
    vm.stopPrank();

    vm.startPrank(receiver_);
    // Receiver claims rewards.
    component.claimRewards(0, receiver_);
    vm.stopPrank();

    // Reward amounts received by `user_` are calculated as: undrippedRewardPool.amount * dripRate *
    // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
    UndrippedRewardPool[] memory undrippedRewardPools_ = component.getUndrippedRewardPools();
    assertApproxEqAbs(undrippedRewardPools_[0].asset.balanceOf(user_), 50, 1); // 100_000 * 0.01 * 0.1 * 0.5
    assertApproxEqAbs(undrippedRewardPools_[1].asset.balanceOf(user_), 12_500_000, 1); // 1_000_000_000 * 0.25 * 0.1 *
      // 0.5
    assertApproxEqAbs(undrippedRewardPools_[2].asset.balanceOf(user_), 499, 1); // 9_999 * 1.0 * 0.1 * 0.5

    // Receiver should receive no rewards.
    assertEq(undrippedRewardPools_[0].asset.balanceOf(receiver_), 0);
    assertEq(undrippedRewardPools_[1].asset.balanceOf(receiver_), 0);
    assertEq(undrippedRewardPools_[2].asset.balanceOf(receiver_), 0);
  }

  function test_revertsOnUnauthorizedUserRewardsUpdate() public {
    vm.startPrank(_randomAddress());
    vm.expectRevert(Ownable.Unauthorized.selector);
    component.updateUserRewardsForStkTokenTransfer(_randomAddress(), _randomAddress());
    vm.stopPrank();
  }
}

contract TestableRewardsHandler is RewardsHandler, Staker, Depositor {
  // -------- Mock setters --------
  function mockSetLastDripTime(uint256 lastDripTime_) external {
    dripTimes.lastRewardsDripTime = uint128(lastDripTime_);
  }

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
  }

  function mockAddUndrippedRewardPool(UndrippedRewardPool memory rewardPool_) external {
    undrippedRewardPools.push(rewardPool_);
  }

  function mockSetUndrippedRewardPool(uint16 i, UndrippedRewardPool memory rewardPool_) external {
    undrippedRewardPools[i] = rewardPool_;
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetClaimableRewardIndex(
    uint16 reservePoolId_,
    uint16 undrippedRewardPoolId_,
    uint256 claimableRewardIndex_
  ) external {
    claimableRewardsIndices[reservePoolId_][undrippedRewardPoolId_] = claimableRewardIndex_;
  }

  function mockRegisterStkToken(uint16 reservePoolId_, IReceiptToken stkToken_) external {
    stkTokenToReservePoolIds[stkToken_] = IdLookup({index: reservePoolId_, exists: true});
  }

  // -------- Mock getters --------
  function getReservePools() external view returns (ReservePool[] memory) {
    return reservePools;
  }

  function getLastDripTime() external view returns (uint256) {
    return dripTimes.lastRewardsDripTime;
  }

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getUndrippedRewardPools() external view returns (UndrippedRewardPool[] memory pools_) {
    pools_ = new UndrippedRewardPool[](undrippedRewardPools.length);
    for (uint256 i = 0; i < pools_.length; i++) {
      pools_[i] = undrippedRewardPools[i];
    }
    return pools_;
  }

  function getUndrippedRewardPool(uint16 undrippedRewardPoolId_) external view returns (UndrippedRewardPool memory) {
    return undrippedRewardPools[undrippedRewardPoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  function getClaimableRewardIndices() external view returns (uint256[][] memory) {
    uint256[][] memory claimableRewardIndices_ = new uint256[][](reservePools.length);
    for (uint16 i = 0; i < reservePools.length; i++) {
      claimableRewardIndices_[i] = new uint256[](undrippedRewardPools.length);
      for (uint16 j = 0; j < undrippedRewardPools.length; j++) {
        claimableRewardIndices_[i][j] = claimableRewardsIndices[i][j];
      }
    }
    return claimableRewardIndices_;
  }

  function getClaimableRewardIndices(uint16 reservePoolId_) external view returns (uint256[] memory) {
    uint256[] memory claimableRewardIndices_ = new uint256[](undrippedRewardPools.length);
    for (uint16 j = 0; j < undrippedRewardPools.length; j++) {
      claimableRewardIndices_[j] = claimableRewardsIndices[reservePoolId_][j];
    }
    return claimableRewardIndices_;
  }

  function getClaimableRewardIndex(uint16 reservePoolId_, uint16 undrippedRewardPoolId_)
    external
    view
    returns (uint256)
  {
    return claimableRewardsIndices[reservePoolId_][undrippedRewardPoolId_];
  }

  function getUserRewards(uint16 reservePoolId_, address user) external view returns (UserRewardsData[] memory) {
    return userRewards[reservePoolId_][user];
  }

  // -------- Exposed internal functions --------
  function getUserAccruedRewards(uint256 stkTokenAmount_, uint256 newRewardPoolIndex, uint256 oldRewardPoolIndex)
    external
    pure
    returns (uint256)
  {
    return _getUserAccruedRewards(stkTokenAmount_, newRewardPoolIndex, oldRewardPoolIndex);
  }

  // -------- Overridden abstract function placeholders --------
  function dripFees() public view override {
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
}
