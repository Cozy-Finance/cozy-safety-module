// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
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
import {AssetPool, ReservePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {
  UserRewardsData,
  PreviewClaimableRewardsData,
  PreviewClaimableRewards,
  ClaimableRewardsData
} from "../src/lib/structs/Rewards.sol";
import {IdLookup} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockStkToken} from "./utils/MockStkToken.sol";
import {MockManager} from "./utils/MockManager.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract RewardsHandlerUnitTest is TestBase {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  MockDripModel mockRewardsDripModel;
  TestableRewardsHandler component = new TestableRewardsHandler();

  uint256 constant DEFAULT_REWARDS_DRIP_RATE = 0.01e18;
  uint256 constant DEFAULT_NUM_RESERVE_POOLS = 2;
  uint256 constant DEFAULT_NUM_REWARD_ASSETS = 3;

  uint256 internal constant ONE_YEAR = 365.25 days;

  event ClaimedRewards(
    uint16 indexed reservePoolId,
    IERC20 indexed rewardAsset_,
    uint256 amount_,
    address indexed owner_,
    address receiver_
  );

  function setUp() public {
    mockRewardsDripModel = new MockDripModel(DEFAULT_REWARDS_DRIP_RATE);
  }

  function _setUpRewardPools(uint256 numRewardAssets_) internal {
    for (uint256 i = 0; i < numRewardAssets_; i++) {
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 amount_ = _randomUint256() % 500_000_000;
      RewardPool memory rewardPool_ = RewardPool({
        asset: IERC20(address(mockAsset_)),
        depositToken: IReceiptToken(address(0)),
        dripModel: IDripModel(mockRewardsDripModel),
        undrippedRewards: amount_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp)
      });
      component.mockAddRewardPool(rewardPool_);

      // Mint safety module rewards.
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
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      });
      component.mockRegisterStkToken(i, stkToken_);
      component.mockAddReservePool(reservePool_);

      mockAsset_.mint(address(component), stakeAmount_ + depositAmount_);
      component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: stakeAmount_ + depositAmount_}));

      // Mint stkTokens and send to zero address to floor supply.
      stkToken_.mint(address(0), _randomUint256() % 500_000_000);
    }
  }

  function _setUpReservePoolsZeroStkTokenSupply(uint256 numReservePools_) internal {
    for (uint16 i = 0; i < numReservePools_; i++) {
      IReceiptToken stkToken_ =
        IReceiptToken(address(new MockStkToken("Mock Cozy  stkToken", "cozyStk", 6, ISafetyModule(address(component)))));
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 depositAmount_ = _randomUint256() % 500_000_000;
      ReservePool memory reservePool_ = ReservePool({
        asset: IERC20(address(mockAsset_)),
        stkToken: stkToken_,
        depositToken: IReceiptToken(address(0)),
        stakeAmount: 0,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: 0,
        pendingWithdrawalsAmount: 0,
        feeAmount: 0,
        rewardsPoolsWeight: (MathConstants.ZOC / numReservePools_).safeCastTo16(),
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      });
      component.mockRegisterStkToken(i, stkToken_);
      component.mockAddReservePool(reservePool_);

      mockAsset_.mint(address(component), depositAmount_);
      component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: depositAmount_}));
    }
  }

  function _setUpClaimableRewards(uint256 numReservePools_, uint256 numRewardAssets_) internal {
    for (uint16 i = 0; i < numReservePools_; i++) {
      for (uint16 j = 0; j < numRewardAssets_; j++) {
        component.mockSetClaimableRewardsData(i, j, uint128(_randomUint256() % 500_000_000));
      }
    }
  }

  function _setUpDefault() internal {
    _setUpReservePools(DEFAULT_NUM_RESERVE_POOLS);
    _setUpRewardPools(DEFAULT_NUM_REWARD_ASSETS);
    _setUpClaimableRewards(DEFAULT_NUM_RESERVE_POOLS, DEFAULT_NUM_REWARD_ASSETS);
  }

  function _setUpConcrete() internal {
    // skip(10);

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
      maxSlashPercentage: MathConstants.WAD,
      lastFeesDripTime: uint128(block.timestamp)
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
      maxSlashPercentage: MathConstants.WAD,
      lastFeesDripTime: uint128(block.timestamp)
    });
    stkToken2_.mint(address(0), 10);
    component.mockAddReservePool(reservePool2_);
    mockAsset2_.mint(address(component), 220e6);
    component.mockAddAssetPool(IERC20(address(mockAsset2_)), AssetPool({amount: 220e6}));

    // Set-up three reward pools.
    {
      RewardPool memory testPool1_;
      MockERC20 asset1_ = new MockERC20("Mock Cozy Reward Token", "rewardToken1", 18);
      IDripModel dripModel1_ = IDripModel(address(new DripModelExponential(318_475_925))); // 1% drip rate

      testPool1_.asset = IERC20(address(asset1_));
      testPool1_.dripModel = dripModel1_;
      testPool1_.undrippedRewards = 100_000;
      testPool1_.lastDripTime = uint128(block.timestamp);
      component.mockAddRewardPool(testPool1_);
      component.mockAddAssetPool(IERC20(address(asset1_)), AssetPool({amount: testPool1_.undrippedRewards}));
      asset1_.mint(address(component), testPool1_.undrippedRewards);
    }
    {
      RewardPool memory testPool2_;
      MockERC20 asset2_ = new MockERC20("Mock Cozy Reward Token", "rewardToken1", 18);
      IDripModel dripModel2_ = IDripModel(address(new DripModelExponential(9_116_094_774))); // 25% annual drip rate

      testPool2_.asset = IERC20(address(asset2_));
      testPool2_.dripModel = dripModel2_;
      testPool2_.undrippedRewards = 1_000_000_000;
      testPool2_.lastDripTime = uint128(block.timestamp);
      component.mockAddRewardPool(testPool2_);
      component.mockAddAssetPool(IERC20(address(asset2_)), AssetPool({amount: testPool2_.undrippedRewards}));
      asset2_.mint(address(component), testPool2_.undrippedRewards);
    }
    {
      RewardPool memory testPool3_;
      MockERC20 asset3_ = new MockERC20("Mock Cozy Reward Token", "rewardToken1", 18);
      IDripModel dripModel3_ = IDripModel(address(new DripModelExponential(145_929_026_605))); // 99% drip rate

      testPool3_.asset = IERC20(address(asset3_));
      testPool3_.dripModel = dripModel3_;
      testPool3_.undrippedRewards = 9999;
      testPool3_.lastDripTime = uint128(block.timestamp);
      component.mockAddRewardPool(testPool3_);
      component.mockAddAssetPool(IERC20(address(asset3_)), AssetPool({amount: testPool3_.undrippedRewards}));
      asset3_.mint(address(component), testPool3_.undrippedRewards);
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

  function _calculateExpectedUpdateToClaimableRewardsData(
    uint256 totalDrippedRewards_,
    uint256 rewardsPoolsWeight_,
    uint256 stkTokenSupply_
  ) internal pure returns (uint256) {
    uint256 scaledDrippedRewards_ = totalDrippedRewards_.mulDivDown(rewardsPoolsWeight_, MathConstants.ZOC);
    return scaledDrippedRewards_.divWadDown(stkTokenSupply_);
  }
}

contract RewardsHandlerDripUnitTest is RewardsHandlerUnitTest {
  function testFuzz_noDripIfSafetyModuleIsPaused(uint64 timeElapsed_) public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    timeElapsed_ = uint64(bound(timeElapsed_, 0, type(uint64).max));
    skip(timeElapsed_);

    RewardPool[] memory initialRewardPools_ = component.getRewardPools();
    ClaimableRewardsData[][] memory initialClaimableRewards_ = component.getClaimableRewards();

    component.dripRewards();
    assertEq(component.getRewardPools(), initialRewardPools_);
    assertEq(component.getClaimableRewards(), initialClaimableRewards_);
  }

  function test_noDripIfNoTimeElapsed() public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    RewardPool[] memory initialRewardPools_ = component.getRewardPools();
    ClaimableRewardsData[][] memory initialClaimableRewards_ = component.getClaimableRewards();

    component.dripRewards();
    assertEq(component.getRewardPools(), initialRewardPools_);
    assertEq(component.getClaimableRewards(), initialClaimableRewards_);
  }

  function test_rewardsDripConcrete() public {
    _setUpConcrete();

    RewardPool[] memory expectedRewardPools_ = new RewardPool[](3);
    RewardPool[] memory concreteRewardPools_ = component.getRewardPools();
    {
      RewardPool memory expectedPool1_;
      expectedPool1_.asset = concreteRewardPools_[0].asset;
      expectedPool1_.dripModel = concreteRewardPools_[0].dripModel;
      expectedPool1_.undrippedRewards = 99_000; // (1 - dripRate) * originalRewardPoolAmount = (1.0 - 0.01) * 100_000
      expectedPool1_.cumulativeDrippedRewards = 1000; // dripRate * originalRewardPoolAmount = 0.01 * 100_000
      expectedPool1_.lastDripTime = uint128(block.timestamp + ONE_YEAR);
      expectedRewardPools_[0] = expectedPool1_;
    }
    {
      RewardPool memory expectedPool2_;
      expectedPool2_.asset = concreteRewardPools_[1].asset;
      expectedPool2_.dripModel = concreteRewardPools_[1].dripModel;
      expectedPool2_.undrippedRewards = 750_000_000; // (1 - dripRate) * originalRewardPoolAmount = (1.0 - 0.25) *
        // 1_000_000_000
      expectedPool2_.cumulativeDrippedRewards = 250_000_000; // dripRate * originalRewardPoolAmount = 0.25 *
        // 1_000_000_000
      expectedPool2_.lastDripTime = uint128(block.timestamp + ONE_YEAR);
      expectedRewardPools_[1] = expectedPool2_;
    }
    {
      RewardPool memory expectedPool3_;
      expectedPool3_.asset = concreteRewardPools_[2].asset;
      expectedPool3_.dripModel = concreteRewardPools_[2].dripModel;
      expectedPool3_.undrippedRewards = 100; // (1 - dripRate) * originalRewardPoolAmount ~= 0.01 * 9999
      expectedPool3_.cumulativeDrippedRewards = 9899; // dripRate * originalRewardPoolAmount ~= 0.99 * 9999
      expectedPool3_.lastDripTime = uint128(block.timestamp + ONE_YEAR);
      expectedRewardPools_[2] = expectedPool3_;
    }

    skip(ONE_YEAR);
    component.dripRewards();
    assertEq(component.getRewardPools(), expectedRewardPools_);
  }

  function testFuzz_rewardsDrip(uint64 timeElapsed_) public {
    _setUpDefault();

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    timeElapsed_ = uint64(bound(timeElapsed_, 1, type(uint64).max));
    skip(timeElapsed_);

    RewardPool[] memory expectedRewardPools_ = component.getRewardPools();

    uint256 numRewardAssets_ = expectedRewardPools_.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      RewardPool memory setUpRewardPool_ = copyRewardPool(expectedRewardPools_[i]);
      uint256 expectedDripRate_ = _randomUint256() % MathConstants.WAD;
      MockDripModel model_ = new MockDripModel(expectedDripRate_);
      setUpRewardPool_.dripModel = model_;

      // Update market with model that has a new drip rate.
      component.mockSetRewardPool(i, setUpRewardPool_);

      // Set up test cases.
      RewardPool memory expectedRewardPool_ = expectedRewardPools_[i];
      expectedRewardPool_.dripModel = model_;
      uint256 totalDrippedAssets_ =
        _calculateExpectedDripQuantity(expectedRewardPool_.undrippedRewards, expectedDripRate_);
      expectedRewardPool_.undrippedRewards -= totalDrippedAssets_;
      expectedRewardPool_.cumulativeDrippedRewards += totalDrippedAssets_;
      expectedRewardPool_.lastDripTime = uint128(block.timestamp);
      expectedRewardPools_[i] = expectedRewardPool_;
    }

    component.dripRewards();
    assertEq(component.getRewardPools(), expectedRewardPools_);
  }

  function test_revertOnInvalidDripFactor() public {
    _setUpDefault();

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    skip(99);

    uint256 dripRate_ = MathConstants.WAD + 1;
    MockDripModel model_ = new MockDripModel(dripRate_);
    // Update a random pool to an invalid drip model.
    uint16 poolId_ = _randomUint16() % uint16(component.getRewardPools().length);
    RewardPool memory rewardPool_ = copyRewardPool(component.getRewardPool(poolId_));
    rewardPool_.dripModel = model_;
    component.mockSetRewardPool(poolId_, rewardPool_);

    vm.expectRevert(ICommonErrors.InvalidDripFactor.selector);
    component.dripRewards();
  }
}

contract RewardsHandlerClaimUnitTest is RewardsHandlerUnitTest {
  using FixedPointMathLib for uint256;

  function test_claimRewardsConcrete() public {
    _setUpConcrete();

    // Get reserve pools and reward pools.
    ReservePool[] memory reservePools_ = component.getReservePools();
    MockERC20 reserveAsset1_ = MockERC20(address(reservePools_[0].asset));
    MockERC20 reserveAsset2_ = MockERC20(address(reservePools_[1].asset));
    RewardPool[] memory rewardPools_ = component.getRewardPools();

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

    skip(ONE_YEAR);

    {
      address receiver_ = _randomAddress();
      _expectEmit();
      emit ClaimedRewards(0, rewardPools_[0].asset, 50, user1, receiver_);
      _expectEmit();
      emit ClaimedRewards(0, rewardPools_[1].asset, 12_500_000, user1, receiver_);
      _expectEmit();
      emit ClaimedRewards(0, rewardPools_[2].asset, 494, user1, receiver_);

      vm.startPrank(user1);
      // User 1 should be transferred 50% of all rewards dripped.
      component.claimRewards(0, receiver_);
      vm.stopPrank();

      // Check cumulative dripped rewards.
      assertEq(component.getRewardPools()[0].cumulativeDrippedRewards, 1000);
      assertEq(component.getRewardPools()[1].cumulativeDrippedRewards, 250_000_000);
      assertEq(component.getRewardPools()[2].cumulativeDrippedRewards, 9899);

      // Reward amounts received by `receiver_` are calculated as: rewardPool.cumulativeDrippedRewards *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply), rounded down.
      assertApproxEqAbs(rewardPools_[0].asset.balanceOf(receiver_), 50, 1); // 1000 * 0.1 * 0.5
      assertApproxEqAbs(rewardPools_[1].asset.balanceOf(receiver_), 12_500_000, 1); // 250_000_000 * 0.1 * 0.5
      assertApproxEqAbs(rewardPools_[2].asset.balanceOf(receiver_), 494, 1); // 9899 * 0.1 * 0.5

      // Since user claimed rewards, accrued rewards should be 0 and index snapshot should be updated.
      UserRewardsData[] memory user1RewardsData_ = component.getUserRewards(0, user1);
      UserRewardsData[] memory expectedUser1RewardsData_ = new UserRewardsData[](3);
      expectedUser1RewardsData_[0] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 0).indexSnapshot});
      expectedUser1RewardsData_[1] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 1).indexSnapshot});
      expectedUser1RewardsData_[2] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 2).indexSnapshot});
      assertEq(user1RewardsData_, expectedUser1RewardsData_);

      // Reward pools should be updated as: rewardPool.undrippedRewards - rewardPool.cumulativeDrippedRewards.
      RewardPool[] memory rewardPoolsUpdated_ = component.getRewardPools();
      assertEq(rewardPoolsUpdated_[0].undrippedRewards, 99_000); // 100_000 - 1000
      assertEq(rewardPoolsUpdated_[1].undrippedRewards, 750_000_000); // 1_000_000_000 - 250_000_000
      assertEq(rewardPoolsUpdated_[2].undrippedRewards, 100); // 9999 - 9899

      // Claimable reward indices should be updated as: oldIndex + [(drippedRewards * rewardsPoolWeight) /
      // stkTokenSupply] * WAD.
      ClaimableRewardsData[][] memory claimableRewards_ = component.getClaimableRewards();
      assertEq(claimableRewards_[0][0].indexSnapshot, 500); // ~= 0 + [(1000 * 0.1) / 0.2e18] * WAD
      assertEq(claimableRewards_[0][1].indexSnapshot, 125_000_000); // ~= 0 + [(250000007 * 0.1) / 0.2e18] * WAD
      assertEq(claimableRewards_[0][2].indexSnapshot, 4945); // ~= 0 + [(9899 * 0.1) / 0.2e18] * WAD

      // Claimable reward indices for reserve pool 1 are not updated since someone has staked for the first time,
      // but there have been no claims or additional stakes on it yet.
      assertEq(claimableRewards_[1][0].indexSnapshot, 0);
      assertEq(claimableRewards_[1][1].indexSnapshot, 0);
      assertEq(claimableRewards_[1][2].indexSnapshot, 0);
    }

    skip(ONE_YEAR);

    vm.prank(user2);
    component.stake(0, 200e6, user2, user2); // Owns 50% of total stake, 400e6

    {
      address receiver_ = _randomAddress();
      vm.startPrank(user1);
      component.claimRewards(0, receiver_);
      vm.stopPrank();

      // Check cumulative dripped rewards.
      assertEq(component.getRewardPools()[0].cumulativeDrippedRewards, 1990);
      assertEq(component.getRewardPools()[1].cumulativeDrippedRewards, 437_500_000);
      assertEq(component.getRewardPools()[2].cumulativeDrippedRewards, 9998);

      // Reward amounts received by `receiver_` are calculated as: (change in rewardPool.cumulativeDrippedRewards) *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply), rounded down.
      // Time skipped one year before the new stake from user 2, so for the entirety of the skip user1 still owned
      // 50% of the totalStkTokenSupply.
      assertApproxEqAbs(rewardPools_[0].asset.balanceOf(receiver_), 49, 1); // 990 * 0.1 * 0.5
      assertApproxEqAbs(rewardPools_[1].asset.balanceOf(receiver_), 9_375_000, 1); // 187_500_000 * 0.1 * 0.5
      assertApproxEqAbs(rewardPools_[2].asset.balanceOf(receiver_), 4, 1); // 99 * 0.1 * 0.5
    }

    skip(ONE_YEAR);

    {
      address receiver1_ = _randomAddress();
      _expectEmit();
      emit ClaimedRewards(0, rewardPools_[0].asset, 49, user2, receiver1_);
      _expectEmit();
      emit ClaimedRewards(0, rewardPools_[1].asset, 7_031_250, user2, receiver1_);
      // Event is not emitted from rewardPool 2 because no rewards are transfered.

      vm.startPrank(user2);
      component.claimRewards(0, receiver1_);
      vm.stopPrank();

      address receiver2_ = _randomAddress();
      _expectEmit();
      emit ClaimedRewards(1, rewardPools_[0].asset, 2138, user2, receiver2_);
      _expectEmit();
      emit ClaimedRewards(1, rewardPools_[1].asset, 416_250_000, user2, receiver2_);
      _expectEmit();
      emit ClaimedRewards(1, rewardPools_[2].asset, 7198, user2, receiver2_);

      vm.startPrank(user2);
      component.claimRewards(1, receiver2_);
      vm.stopPrank();

      // Check cumulative dripped rewards.
      assertEq(component.getRewardPools()[0].cumulativeDrippedRewards, 2970);
      assertEq(component.getRewardPools()[1].cumulativeDrippedRewards, 578_125_000);
      assertEq(component.getRewardPools()[2].cumulativeDrippedRewards, 9998);

      // Reward amounts received by `receiver1_` are calculated as: change in rewardPool.cumulativeDrippedRewards *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply) rounded down.
      assertApproxEqAbs(rewardPools_[0].asset.balanceOf(receiver1_), 49, 1); // 980 * 0.1 * 0.5
      assertApproxEqAbs(rewardPools_[1].asset.balanceOf(receiver1_), 7_031_250, 1); // 140625000 * 0.1 * 0.5
      assertApproxEqAbs(rewardPools_[2].asset.balanceOf(receiver1_), 0, 1); // 0 * 0.1 * 0.5

      // Reward amounts received by `receiver2_` are calculated as: rewardPool.cumulativeDrippedRewards *
      // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply) rounded down. They do not use the change
      // in cumulativeDrippedRewards since this is the first time user2 is claiming from pool 1, and their
      // stake was before all the time skips.
      assertApproxEqAbs(rewardPools_[0].asset.balanceOf(receiver2_), 2138, 1); // 2970 * 0.9 * 0.8
      assertApproxEqAbs(rewardPools_[1].asset.balanceOf(receiver2_), 416_250_000, 1); // 578125000 * 0.9 * 0.8
      assertApproxEqAbs(rewardPools_[2].asset.balanceOf(receiver2_), 7198, 1); // 9998 * 0.9 * 0.8

      // Since user claimed full rewards, user's accrued rewards should be 0 and index snapshot should be updated.
      UserRewardsData[] memory user2RewardsData1_ = component.getUserRewards(0, user2);
      UserRewardsData[] memory expectedUser2RewardsData1_ = new UserRewardsData[](3);
      expectedUser2RewardsData1_[0] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 0).indexSnapshot});
      expectedUser2RewardsData1_[1] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 1).indexSnapshot});
      expectedUser2RewardsData1_[2] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 2).indexSnapshot});
      assertEq(user2RewardsData1_, expectedUser2RewardsData1_);

      UserRewardsData[] memory user2RewardsData2_ = component.getUserRewards(1, user2);
      UserRewardsData[] memory expectedUser2RewardsData2_ = new UserRewardsData[](3);
      expectedUser2RewardsData2_[0] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(1, 0).indexSnapshot});
      expectedUser2RewardsData2_[1] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(1, 1).indexSnapshot});
      expectedUser2RewardsData2_[2] =
        UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(1, 2).indexSnapshot});
      assertEq(user2RewardsData2_, expectedUser2RewardsData2_);
    }
  }

  function testFuzz_previewClaimableRewards(uint64 timeElapsed_) public {
    _setUpDefault();

    (address user_, uint16 reservePoolId_, address receiver_) = _getUserClaimRewardsFixture();
    vm.assume(reservePoolId_ != 0);

    // Compute original number of reward pools.
    uint256 oldNumRewardPools_ = component.getRewardPools().length;

    // Add new reward asset pool.
    {
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 newRewardPoolAmount_ = _randomUint256() % 500_000_000;
      RewardPool memory rewardPool_ = RewardPool({
        asset: IERC20(address(mockAsset_)),
        depositToken: IReceiptToken(address(0)),
        dripModel: IDripModel(mockRewardsDripModel),
        undrippedRewards: newRewardPoolAmount_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp)
      });
      component.mockAddRewardPool(rewardPool_);
      // Mint safety module rewards.
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
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    PreviewClaimableRewardsData[] memory expectedPreviewClaimableRewardsData_ =
      new PreviewClaimableRewardsData[](rewardPools_.length);
    PreviewClaimableRewardsData[] memory expectedPreviewClaimableRewardsDataPool0_ =
      new PreviewClaimableRewardsData[](rewardPools_.length);
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      IERC20 asset_ = rewardPools_[i].asset;
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

  function test_previewClaimableRewardsWhenPaused() public {
    _setUpDefault();

    address user_ = _randomAddress();
    uint16 reservePoolId_ = 0;
    uint256 reserveAssetAmount_ = 100e18;

    // Mint user reserve assets.
    ReservePool memory reservePool_ = component.getReservePool(reservePoolId_);
    MockERC20 mockAsset_ = MockERC20(address(reservePool_.asset));
    mockAsset_.mint(user_, reserveAssetAmount_);

    vm.prank(user_);
    mockAsset_.approve(address(component), type(uint256).max);
    component.stake(reservePoolId_, reserveAssetAmount_, user_, user_);
    vm.stopPrank();

    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    skip(30 days);

    // User previews reservePoolId_ (the pool they staked into).
    uint16[] memory previewReservePoolIds_ = new uint16[](1);
    previewReservePoolIds_[0] = reservePoolId_;
    PreviewClaimableRewards[] memory previewClaimableRewards_ =
      component.previewClaimableRewards(previewReservePoolIds_, user_);
    assertEq(previewClaimableRewards_[reservePoolId_].claimableRewardsData[0].amount, 0);
    assertEq(previewClaimableRewards_[reservePoolId_].claimableRewardsData[1].amount, 0);
    assertEq(previewClaimableRewards_[reservePoolId_].claimableRewardsData[2].amount, 0);

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    skip(30 days);

    // Previews should not return 0 because the safety module has been active.
    previewClaimableRewards_ = component.previewClaimableRewards(previewReservePoolIds_, user_);
    uint256[] memory claimableRewardsAmounts_ = new uint256[](3);
    claimableRewardsAmounts_[0] = previewClaimableRewards_[reservePoolId_].claimableRewardsData[0].amount;
    claimableRewardsAmounts_[1] = previewClaimableRewards_[reservePoolId_].claimableRewardsData[1].amount;
    claimableRewardsAmounts_[2] = previewClaimableRewards_[reservePoolId_].claimableRewardsData[2].amount;
    assertTrue(previewClaimableRewards_[reservePoolId_].claimableRewardsData[0].amount > 0);
    assertTrue(previewClaimableRewards_[reservePoolId_].claimableRewardsData[1].amount > 0);
    assertTrue(previewClaimableRewards_[reservePoolId_].claimableRewardsData[2].amount > 0);

    // Mock pausing, where rewards are dripped.
    component.dripRewards();
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    skip(30 days);

    // Previews should not change because the safety module has been paused.
    previewClaimableRewards_ = component.previewClaimableRewards(previewReservePoolIds_, user_);
    assertEq(previewClaimableRewards_[reservePoolId_].claimableRewardsData[0].amount, claimableRewardsAmounts_[0]);
    assertEq(previewClaimableRewards_[reservePoolId_].claimableRewardsData[1].amount, claimableRewardsAmounts_[1]);
    assertEq(previewClaimableRewards_[reservePoolId_].claimableRewardsData[2].amount, claimableRewardsAmounts_[2]);
  }

  function testFuzz_claimRewards(uint64 timeElapsed_) public {
    _setUpDefault();

    (address user_, uint16 reservePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    skip(timeElapsed_);
    uint256 userStkTokenBalance_ = component.getReservePool(reservePoolId_).stkToken.balanceOf(user_);
    ClaimableRewardsData[] memory oldClaimableRewards_ = component.getClaimableRewards(reservePoolId_);

    // User claims rewards.
    vm.prank(user_);
    component.claimRewards(reservePoolId_, receiver_);

    // Check receiver balances and user rewards data.
    ClaimableRewardsData[] memory newClaimableRewards_ = component.getClaimableRewards(reservePoolId_);
    UserRewardsData[] memory newUserRewards_ = component.getUserRewards(reservePoolId_, user_);
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      IERC20 asset_ = rewardPools_[i].asset;
      uint256 accruedRewards_ = component.getUserAccruedRewards(
        userStkTokenBalance_, newClaimableRewards_[i].indexSnapshot, oldClaimableRewards_[i].indexSnapshot
      );
      assertApproxEqAbs(asset_.balanceOf(receiver_), accruedRewards_, 1);
      assertApproxEqAbs(newUserRewards_[i].indexSnapshot, newClaimableRewards_[i].indexSnapshot, 1);
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
    _setUpRewardPools(numRewardsPools_);
    _setUpClaimableRewards(DEFAULT_NUM_RESERVE_POOLS, numRewardsPools_);

    (address user_, uint16 reservePoolId_, address receiver_) = _getUserClaimRewardsFixture();

    // Add new reward asset pool.
    MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
    {
      uint256 amount_ = 9000;
      RewardPool memory rewardPool_ = RewardPool({
        asset: IERC20(address(mockAsset_)),
        depositToken: IReceiptToken(address(0)),
        dripModel: IDripModel(mockRewardsDripModel),
        undrippedRewards: amount_,
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp)
      });
      component.mockAddRewardPool(rewardPool_);
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
      component.getClaimableRewardsData(reservePoolId_, uint16(numRewardsPools_)).indexSnapshot
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
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    for (uint16 i = 0; i < rewardPools_.length; i++) {
      assertEq(rewardPools_[i].asset.balanceOf(newReceiver_), 0);
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

    // User transfers all stkTokens to receiver.
    IERC20 stkToken_ = component.getReservePool(0).stkToken;
    vm.startPrank(user_);
    stkToken_.transfer(receiver_, originalUserStkTokenAmount_);
    vm.stopPrank();

    // Time passes, user stakes again. Again, user owns 50% of the new total stake, 400e6.
    vm.startPrank(user_);
    component.stake(0, 200e6, user_, user_);
    vm.stopPrank();

    skip(ONE_YEAR);

    assertEq(component.getRewardPools()[0].cumulativeDrippedRewards, 0);

    // Both users claim rewards.
    vm.prank(user_);
    component.claimRewards(0, user_);
    vm.prank(receiver_);
    component.claimRewards(0, receiver_);

    // Check rewards balances.
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    assertEq(rewardPools_[0].cumulativeDrippedRewards, 1000);
    assertEq(rewardPools_[1].cumulativeDrippedRewards, 250_000_000);
    assertEq(rewardPools_[2].cumulativeDrippedRewards, 9899);

    // Rewards received are equal to the amount dripped from each reward pool * rewardsPoolWeight * (userStkTokenBalance
    // / totalStkTokenSupply).
    assertApproxEqAbs(rewardPools_[0].asset.balanceOf(user_), 50, 1); // ~= 1000 * 0.1 * 0.5
    assertApproxEqAbs(rewardPools_[1].asset.balanceOf(user_), 12_500_000, 1); // ~= 250000007 * 0.1 * 0.5
    assertApproxEqAbs(rewardPools_[2].asset.balanceOf(user_), 494, 1); // ~= 9899 * 0.1 * 0.5
    assertApproxEqAbs(rewardPools_[0].asset.balanceOf(receiver_), 25, 1); // ~= 1000 * 0.1 * 0.25
    assertApproxEqAbs(rewardPools_[1].asset.balanceOf(receiver_), 6_249_999, 1); // ~= 250000007 * 0.1 * 0.25
    assertApproxEqAbs(rewardPools_[2].asset.balanceOf(receiver_), 247, 1); // ~= 9899 * 0.1 * 0.25
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

    skip(ONE_YEAR);

    vm.startPrank(user_);
    // User claims rewards.
    component.claimRewards(0, user_);
    vm.stopPrank();

    // Check user rewards balances.
    RewardPool[] memory rewardPools_ = component.getRewardPools();

    // Reward amounts received by `user_` are calculated as: rewardPool.amount * dripRate *
    // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
    assertApproxEqAbs(rewardPools_[0].asset.balanceOf(user_), 37, 1); // 100_000 * 0.01 * 0.1 * (0.5 * 0.75)
    assertApproxEqAbs(rewardPools_[1].asset.balanceOf(user_), 9_375_000, 1); // 1_000_000_000 * 0.25 * 0.1 *
      // (0.5 * 0.75)
    assertApproxEqAbs(rewardPools_[2].asset.balanceOf(user_), 370, 1); // 9_999 * 1.0 * 0.1 * (0.5 * 0.75)

    // Check user rewards data.
    UserRewardsData[] memory userRewardsData_ = component.getUserRewards(0, user_);
    UserRewardsData[] memory expectedUserRewardsData_ = new UserRewardsData[](3);
    expectedUserRewardsData_[0] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 0).indexSnapshot});
    expectedUserRewardsData_[1] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 1).indexSnapshot});
    expectedUserRewardsData_[2] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 2).indexSnapshot});
    assertEq(userRewardsData_, expectedUserRewardsData_);

    skip(ONE_YEAR); // Will induce another drip of rewards
    vm.startPrank(receiver_);
    // Receiver claims rewards.
    component.claimRewards(0, receiver_);
    vm.stopPrank();

    // Check user rewards balances.
    assertApproxEqAbs(rewardPools_[0].asset.balanceOf(receiver_), 24, 1); // (100_000 + 99_000) * 0.01 * 0.1 *
      // (0.5 * 0.25)
    assertApproxEqAbs(rewardPools_[1].asset.balanceOf(receiver_), 5_468_750, 1); // (1_000_000_000 +
      // 750_000_000) * 0.25 * 0.1 * (0.5 * 0.25)
    assertApproxEqAbs(rewardPools_[2].asset.balanceOf(receiver_), 124, 1); // (9_999 + 0) * 1.0 * 0.1 * (0.5 *
      // 0.25)

    // Check user rewards data.
    UserRewardsData[] memory receiverRewardsData_ = component.getUserRewards(0, receiver_);
    UserRewardsData[] memory expectedReceiverRewardsData_ = new UserRewardsData[](3);
    expectedReceiverRewardsData_[0] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 0).indexSnapshot});
    expectedReceiverRewardsData_[1] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 1).indexSnapshot});
    expectedReceiverRewardsData_[2] =
      UserRewardsData({accruedRewards: 0, indexSnapshot: component.getClaimableRewardsData(0, 2).indexSnapshot});
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
    skip(ONE_YEAR);

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

    // Reward amounts received by `user_` are calculated as: rewardPool.amount * dripRate *
    // rewardsPoolWeight * (userStkTokenBalance / totalStkTokenSupply).
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    assertApproxEqAbs(rewardPools_[0].asset.balanceOf(user_), 50, 1); // 100_000 * 0.01 * 0.1 * 0.5
    assertApproxEqAbs(rewardPools_[1].asset.balanceOf(user_), 12_500_000, 1); // 1_000_000_000 * 0.25 * 0.1 *
      // 0.5
    assertApproxEqAbs(rewardPools_[2].asset.balanceOf(user_), 494, 1); // 9_999 * 1.0 * 0.1 * 0.5

    // Receiver should receive no rewards.
    assertEq(rewardPools_[0].asset.balanceOf(receiver_), 0);
    assertEq(rewardPools_[1].asset.balanceOf(receiver_), 0);
    assertEq(rewardPools_[2].asset.balanceOf(receiver_), 0);
  }

  function test_revertsOnUnauthorizedUserRewardsUpdate() public {
    vm.startPrank(_randomAddress());
    vm.expectRevert(Ownable.Unauthorized.selector);
    component.updateUserRewardsForStkTokenTransfer(_randomAddress(), _randomAddress());
    vm.stopPrank();
  }
}

contract RewardsHandlerDripAndResetCumulativeValuesUnitTest is RewardsHandlerUnitTest {
  function _expectedClaimableRewardsData(uint128 indexSnapshot) internal pure returns (ClaimableRewardsData memory) {
    return ClaimableRewardsData({indexSnapshot: indexSnapshot, cumulativeClaimedRewards: 0});
  }

  function testFuzz_dripAndResetCumulativeRewardsValuesZeroStkTokenSupply() public {
    _setUpReservePoolsZeroStkTokenSupply(1);
    _setUpRewardPools(1);
    _setUpClaimableRewards(1, 1);
    skip(_randomUint64());

    ClaimableRewardsData[][] memory initialClaimableRewards_ = component.getClaimableRewards();
    RewardPool[] memory expectedRewardPools_ = component.getRewardPools();

    component.dripAndResetCumulativeRewardsValues();

    ClaimableRewardsData[][] memory claimableRewards_ = component.getClaimableRewards();
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    expectedRewardPools_[0].lastDripTime = uint128(block.timestamp);
    expectedRewardPools_[0].undrippedRewards -=
      _calculateExpectedDripQuantity(expectedRewardPools_[0].undrippedRewards, DEFAULT_REWARDS_DRIP_RATE);

    assertEq(claimableRewards_[0][0], _expectedClaimableRewardsData(initialClaimableRewards_[0][0].indexSnapshot));
    assertEq(expectedRewardPools_, rewardPools_);
  }

  function test_dripAndResetCumulativeRewardsValuesConcrete() public {
    _setUpConcrete();
    skip(ONE_YEAR);
    component.dripAndResetCumulativeRewardsValues();

    ClaimableRewardsData[][] memory claimableRewards_ = component.getClaimableRewards();
    // Claimable reward indices should be updated as [(drippedRewards * rewardsPoolWeight) / stkTokenSupply] * WAD.
    // Cumulative claimed rewards should be the drippedRewards. Cumulative claimed rewards should be reset to 0.
    assertEq(claimableRewards_[0][0], _expectedClaimableRewardsData(1000)); // [(100_000 * 0.01 * 0.1) / 0.1e18] *
      // WAD
    assertEq(claimableRewards_[0][1], _expectedClaimableRewardsData(250_000_000)); // [(1_000_000_000 * 0.25 *
      // 0.1) / 0.1e18] * WAD
    assertEq(claimableRewards_[0][2], _expectedClaimableRewardsData(9890)); // [(9890 * 1 * 0.1) / 0.1e18] * WAD
    assertEq(claimableRewards_[1][0], _expectedClaimableRewardsData(90e18)); // [(100_000 * 0.01 * 0.9) / 10] *
      // WAD
    assertEq(claimableRewards_[1][1], _expectedClaimableRewardsData(2.25e25)); // [(1_000_000_000 * 0.25 *
      // 0.9) / 10] * WAD
    assertEq(claimableRewards_[1][2], _expectedClaimableRewardsData(8.909e20)); // [(9999 * 1 * 0.9) / 10] * WAD

    // Cumulative claimed rewards here should match the sum of the cumulative claimed rewards.
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    assertEq(rewardPools_[0].cumulativeDrippedRewards, 0);
    assertEq(rewardPools_[1].cumulativeDrippedRewards, 0);
    assertEq(rewardPools_[2].cumulativeDrippedRewards, 0);
  }

  function testFuzz_dripAndResetCumulativeValues() public {
    _setUpDefault();
    component.dripAndResetCumulativeRewardsValues();

    ClaimableRewardsData[][] memory claimableRewards_ = component.getClaimableRewards();
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    ReservePool[] memory reservePools_ = component.getReservePools();

    // Check that cmulative claimed rewards here match the sum of the cumulative claimed rewards.
    uint256 numRewardPools_ = rewardPools_.length;
    uint256 numReservePools_ = reservePools_.length;

    for (uint16 i = 0; i < numRewardPools_; i++) {
      assertEq(rewardPools_[i].cumulativeDrippedRewards, 0);
      for (uint16 j = 0; j < numReservePools_; j++) {
        assertEq(claimableRewards_[j][i].cumulativeClaimedRewards, 0);
      }
    }
  }
}

contract TestableRewardsHandler is RewardsHandler, Staker, Depositor {
  // -------- Mock setters --------
  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockSetRewardPool(uint16 i, RewardPool memory rewardPool_) external {
    rewardPools[i] = rewardPool_;
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetClaimableRewardsData(uint16 reservePoolId_, uint16 rewardPoolid_, uint128 claimableRewardsIndex_)
    external
  {
    claimableRewards[reservePoolId_][rewardPoolid_] =
      ClaimableRewardsData({indexSnapshot: claimableRewardsIndex_, cumulativeClaimedRewards: 0});
  }

  function mockRegisterStkToken(uint16 reservePoolId_, IReceiptToken stkToken_) external {
    stkTokenToReservePoolIds[stkToken_] = IdLookup({index: reservePoolId_, exists: true});
  }

  // -------- Mock getters --------
  function getReservePools() external view returns (ReservePool[] memory) {
    return reservePools;
  }

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getRewardPools() external view returns (RewardPool[] memory pools_) {
    pools_ = new RewardPool[](rewardPools.length);
    for (uint256 i = 0; i < pools_.length; i++) {
      pools_[i] = rewardPools[i];
    }
    return pools_;
  }

  function getRewardPool(uint16 rewardPoolid_) external view returns (RewardPool memory) {
    return rewardPools[rewardPoolid_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  function getClaimableRewards() external view returns (ClaimableRewardsData[][] memory) {
    ClaimableRewardsData[][] memory claimableRewards_ = new ClaimableRewardsData[][](reservePools.length);
    for (uint16 i = 0; i < reservePools.length; i++) {
      claimableRewards_[i] = new ClaimableRewardsData[](rewardPools.length);
      for (uint16 j = 0; j < rewardPools.length; j++) {
        claimableRewards_[i][j] = claimableRewards[i][j];
      }
    }
    return claimableRewards_;
  }

  function getClaimableRewards(uint16 reservePoolId_) external view returns (ClaimableRewardsData[] memory) {
    ClaimableRewardsData[] memory claimableRewards_ = new ClaimableRewardsData[](rewardPools.length);
    for (uint16 j = 0; j < rewardPools.length; j++) {
      claimableRewards_[j] = claimableRewards[reservePoolId_][j];
    }
    return claimableRewards_;
  }

  function getClaimableRewardsData(uint16 reservePoolId_, uint16 rewardPoolid_)
    external
    view
    returns (ClaimableRewardsData memory)
  {
    return claimableRewards[reservePoolId_][rewardPoolid_];
  }

  function getUserRewards(uint16 reservePoolId_, address user) external view returns (UserRewardsData[] memory) {
    return userRewards[reservePoolId_][user];
  }

  // -------- Exposed internal functions --------
  function getUserAccruedRewards(uint256 stkTokenAmount_, uint128 newRewardPoolIndex, uint128 oldRewardPoolIndex)
    external
    pure
    returns (uint256)
  {
    return _getUserAccruedRewards(stkTokenAmount_, newRewardPoolIndex, oldRewardPoolIndex);
  }

  function dripAndResetCumulativeRewardsValues() external {
    _dripAndResetCumulativeRewardsValues(reservePools, rewardPools);
  }

  // -------- Overridden abstract function placeholders --------
  function dripFees() public view override {
    __readStub__();
  }

  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    ReservePool storage, /* reservePool_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    ReservePool storage, /* reservePool_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _dripFeesFromReservePool(ReservePool storage, /* reservePool_*/ IDripModel /*dripModel_*/ )
    internal
    view
    override
  {
    __readStub__();
  }
}
