// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {DripModelConstant} from "cozy-safety-module-models/DripModelConstant.sol";
import {DripModelConstantFactory} from "cozy-safety-module-models/DripModelConstantFactory.sol";
import {IDripModelConstantFactory} from "cozy-safety-module-models/interfaces/IDripModelConstantFactory.sol";
import {CozyManager} from "cozy-safety-module-rewards-manager/CozyManager.sol";
import {RewardsManager} from "cozy-safety-module-rewards-manager/RewardsManager.sol";
import {RewardsManagerFactory} from "cozy-safety-module-rewards-manager/RewardsManagerFactory.sol";
import {StkReceiptToken} from "cozy-safety-module-rewards-manager/StkReceiptToken.sol";
import {StakePoolConfig, RewardPoolConfig} from "cozy-safety-module-rewards-manager/lib/structs/Configs.sol";
import {ICozyManager} from "cozy-safety-module-rewards-manager/interfaces/ICozyManager.sol";
import {IRewardsManager} from "cozy-safety-module-rewards-manager/interfaces/IRewardsManager.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {ChainlinkTriggerFactory} from "cozy-safety-module-triggers/src/ChainlinkTriggerFactory.sol";
import {OwnableTriggerFactory} from "cozy-safety-module-triggers/src/OwnableTriggerFactory.sol";
import {OptimisticOracleV2Interface} from "cozy-safety-module-triggers/src/interfaces/OptimisticOracleV2Interface.sol";
import {UMATriggerFactory} from "cozy-safety-module-triggers/src/UMATriggerFactory.sol";
import {MockChainlinkOracle} from "cozy-safety-module-triggers/test/utils/MockChainlinkOracle.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {CozyRouterAvax} from "../src/CozyRouterAvax.sol";
import {TokenHelpers} from "../src/lib/router/TokenHelpers.sol";
import {CozyRouterCommon} from "../src/lib/router/CozyRouterCommon.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {ReservePoolConfig, TriggerConfig, UpdateConfigsCalldataParams} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {ReservePool} from "../src/lib/structs/Pools.sol";
import {TriggerMetadata} from "../src/lib/structs/Trigger.sol";
import {TriggerFactories} from "../src/lib/structs/TriggerFactories.sol";
import {IChainlinkTriggerFactory} from "../src/interfaces/IChainlinkTriggerFactory.sol";
import {IMetadataRegistry} from "../src/interfaces/IMetadataRegistry.sol";
import {IOwnableTriggerFactory} from "../src/interfaces/IOwnableTriggerFactory.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {IStETH} from "../src/interfaces/IStETH.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {IUMATriggerFactory} from "../src/interfaces/IUMATriggerFactory.sol";
import {IWeth} from "../src/interfaces/IWeth.sol";
import {IWstETH} from "../src/interfaces/IWstETH.sol";
import {MockConnector} from "./utils/MockConnector.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {MockMetadataRegistry} from "./utils/MockMetadataRegistry.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";
import {MockUMAOracle} from "./utils/MockUMAOracle.sol";

abstract contract CozyRouterTestSetup is MockDeployProtocol {
  CozyRouter router;
  ISafetyModule safetyModule;
  IStETH stEth;
  IWstETH wstEth;
  IChainlinkTriggerFactory chainlinkTriggerFactory = IChainlinkTriggerFactory(address(new ChainlinkTriggerFactory()));
  IOwnableTriggerFactory ownableTriggerFactory = IOwnableTriggerFactory(address(new OwnableTriggerFactory()));
  OptimisticOracleV2Interface umaOracle = OptimisticOracleV2Interface(address(new MockUMAOracle())); // Mock for tests.
  IUMATriggerFactory umaTriggerFactory = IUMATriggerFactory(address(new UMATriggerFactory(umaOracle)));

  IERC20 reserveAssetA = IERC20(address(new MockERC20("Mock Reserve Asset", "MOCKRES", 6)));
  // IERC20 rewardAssetA = IERC20(address(new MockERC20("Mock Reward Asset", "MOCKREW", 6)));
  ITrigger trigger = ITrigger(new MockTrigger(TriggerState.ACTIVE));

  address alice = address(0xABCD);
  address bob = address(0xDCBA);
  address self = address(this);

  // For calculating the per-second decay/drip rate, we use the exponential decay formula A = P * (1 - r) ^ t
  // where A is final amount, P is principal (starting) amount, r is the per-second decay rate, and t is the number of
  // elapsed seconds.
  // For example, for an annual decay rate of 25%:
  // A = P * (1 - r) ^ t
  // 0.75 = 1 * (1 - r) ^ 31557600
  // -r = 0.75^(1/31557600) - 1
  // -r = -9.116094732822280932149636651070655494101566187385032e-9
  // Multiplying r by -1e18 to calculate the scaled up per-second value required by decay/drip model constructors ~=
  // 9116094774
  uint256 constant DECAY_RATE_PER_SECOND = 9_116_094_774; // Per-second decay rate of 25% annually.

  uint16 constant ALLOWED_NUM_STAKE_POOLS = 100;
  uint16 constant ALLOWED_NUM_REWARD_POOLS = 100;

  uint8 wethReservePoolId;
  uint8 wethRewardPoolId;

  /// @dev Emitted by ERC20s when `amount` tokens are moved from `from` to `to`.
  event Transfer(address indexed from, address indexed to, uint256 amount);

  struct ChainlinkTriggerParams {
    AggregatorV3Interface truthOracle;
    AggregatorV3Interface trackingOracle;
    uint256 priceTolerance;
    uint256 truthFrequencyTolerance;
    uint256 trackingFrequencyTolerance;
  }

  struct OwnableTriggerParams {
    address owner;
    bytes32 salt;
  }

  struct UMATriggerParams {
    string query;
    IERC20 rewardToken;
    uint256 rewardAmount;
    address refundRecipient;
    uint256 bondAmount;
    uint256 proposalDisputeWindow;
  }

  function setUp() public virtual override {
    super.setUp();

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = ReservePoolConfig({maxSlashPercentage: 0, asset: reserveAssetA});
    reservePoolConfigs_[1] = ReservePoolConfig({maxSlashPercentage: 0, asset: IERC20(address(weth))});
    wethReservePoolId = 1;

    // RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](2);
    // rewardPoolConfigs_[0] = RewardPoolConfig({
    //   asset: IERC20(address(weth)),
    //   dripModel: IDripModel(address(new MockDripModel(DECAY_RATE_PER_SECOND)))
    // });
    // rewardPoolConfigs_[1] =
    //   RewardPoolConfig({asset: rewardAssetA, dripModel: IDripModel(address(new
    // MockDripModel(DECAY_RATE_PER_SECOND)))});
    // wethRewardPoolId = 0;

    Delays memory delaysConfig_ =
      Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: trigger, payoutHandler: _randomAddress(), exists: true});

    safetyModule = ISafetyModule(
      address(
        SafetyModule(
          address(
            manager.createSafetyModule(
              self,
              self,
              UpdateConfigsCalldataParams({
                reservePoolConfigs: reservePoolConfigs_,
                triggerConfigUpdates: triggerConfig_,
                delaysConfig: delaysConfig_
              }),
              _randomBytes32()
            )
          )
        )
      )
    );

    router = new CozyRouter(
      manager,
      ICozyManager(address(0)),
      weth,
      stEth,
      wstEth,
      TriggerFactories({
        chainlinkTriggerFactory: chainlinkTriggerFactory,
        ownableTriggerFactory: ownableTriggerFactory,
        umaTriggerFactory: umaTriggerFactory
      }),
      IDripModelConstantFactory(address(0))
    );
  }
}

contract CozyRouterAggregateTest is CozyRouterTestSetup {
  // TODO This just a single example of how the router might be used. We should have more tests of this behavior.
  function testFuzz_BatchesCalls(uint88 amount_) public {
    vm.assume(amount_ > 100);
    uint256 ethAmount_ = uint256(amount_);
    deal(address(this), ethAmount_);

    bytes[] memory calls_ = new bytes[](2);
    uint8 reservePoolId_ = 1; // The weth reserve pool ID.

    calls_[0] = abi.encodeWithSelector(bytes4(keccak256(bytes("wrapNativeToken(address)"))), (address(safetyModule)));
    calls_[1] = abi.encodeWithSelector(
      router.depositReserveAssetsWithoutTransfer.selector,
      address(safetyModule),
      reservePoolId_,
      ethAmount_,
      address(this)
    );

    router.aggregate{value: ethAmount_}(calls_);

    ReservePool memory reservePoolB_ = getReservePool(safetyModule, reservePoolId_);

    assertEq(reservePoolB_.depositReceiptToken.balanceOf(address(this)), ethAmount_);
    assertEq(weth.balanceOf(address(safetyModule)), ethAmount_);
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(address(router).balance, 0);
    assertEq(address(this).balance, 0);
  }

  function test_RevertsWithFailureData() public {}
  function test_SweepEthUsingAggregate() public {
    // Sweep ETH out by wrapping ETH and sending to router then unwrapping to recipient.
  }
}

// Abstract test contract base with some helpers for
// manipulating WEth token balance in the Router.
abstract contract CozyWEthHelperTest is CozyRouterTestSetup {
  function dealAndDepositEth(uint128 _amount) public {
    vm.startPrank(address(router));
    vm.deal(address(router), _amount);
    weth.deposit{value: _amount}();
    assertEq(weth.balanceOf(address(router)), _amount);
    vm.stopPrank();
  }
}

contract CozyRouterPermitTest is CozyRouterTestSetup {
  bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  function computeDomainSeparator(IERC20 _token) public view returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes(_token.name())),
        keccak256("1"),
        block.chainid,
        address(_token)
      )
    );
  }

  function _testPermitIERC20Token(IERC20 token_, uint256 privateKey_, uint256 amount_, uint256 deadline_) internal {
    address _owner = vm.addr(privateKey_);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      privateKey_,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          computeDomainSeparator(token_),
          keccak256(abi.encode(PERMIT_TYPEHASH, _owner, address(router), amount_, 0, deadline_))
        )
      )
    );

    vm.prank(_owner);
    router.permitRouter(token_, amount_, deadline_, v, r, s);

    assertEq(token_.allowance(_owner, address(router)), amount_);
    assertEq(token_.nonces(_owner), 1);
  }

  // TODO: Implement 2612 and dai permit tests.
  // USDC uses ERC-2612 for permit, DAI uses a slightly different format, but we this method should work for both.
  function test_PermitsErc2612() public {}
  function test_PermitsDai() public {}

  function test_PermitRouterDepositAndStakeTokens(uint248 privKey, uint256 amount, uint256 deadline) public {
    uint256 privateKey = privKey;
    if (deadline < block.timestamp) deadline = block.timestamp;
    if (privateKey == 0) privateKey = 1;

    ReservePool memory reservePool_ = getReservePool(safetyModule, 0);
    IERC20 depositReceiptToken_ = reservePool_.depositReceiptToken;
    // IERC20 stakeToken_ = reservePool_.stkToken;

    _testPermitIERC20Token(depositReceiptToken_, privateKey, amount, deadline);
    // _testPermitIERC20Token(stakeToken_, privateKey, amount, deadline);
  }
}

contract CozyRouterSweepTokenTest is CozyWEthHelperTest {
  function test_SweepToken() public {
    testFuzz_SweepToken(5, 10);
  }

  function testFuzz_SweepToken(uint128 amountMin_, uint128 routerBalance_) public {
    amountMin_ = uint128(bound(amountMin_, 0, type(uint128).max));
    routerBalance_ = uint128(bound(routerBalance_, amountMin_, type(uint128).max));
    dealAndDepositEth(routerBalance_);
    router.sweepToken(IERC20(address(weth)), address(alice), amountMin_);
    assertEq(weth.balanceOf(address(alice)), routerBalance_);
    assertEq(weth.balanceOf(address(router)), 0);
  }

  function test_AmountMinIsRespected() public {
    testFuzz_AmountMinIsRespected(10, 5);
  }

  function testFuzz_AmountMinIsRespected(uint128 amountMin_, uint128 invalidBalance_) public {
    amountMin_ = uint128(bound(amountMin_, 1, type(uint128).max));
    invalidBalance_ = uint128(bound(invalidBalance_, 0, amountMin_ - 1));
    dealAndDepositEth(invalidBalance_);
    vm.expectRevert(TokenHelpers.InsufficientBalance.selector);
    router.sweepToken(IERC20(address(weth)), address(alice), amountMin_);
  }

  function test_SweepTokenRevertsIfZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.sweepToken(IERC20(address(weth)), address(0), 10);
  }
}

contract CozyRouterTransferTokensTest is CozyWEthHelperTest {
  function test_TransferTokens() public {
    testFuzz_TransferTokens(5, 10);
  }

  function testFuzz_TransferTokens(uint128 _amount, uint128 _routerBalance) public {
    _amount = uint128(bound(_amount, 0, type(uint128).max));
    _routerBalance = uint128(bound(_routerBalance, _amount, type(uint128).max));
    dealAndDepositEth(_routerBalance);
    router.transferTokens(IERC20(address(weth)), address(alice), _amount);
    assertEq(weth.balanceOf(address(alice)), _amount);
    assertEq(weth.balanceOf(address(router)), _routerBalance - _amount);
  }

  function test_TransferTokensRevertsIfRecipientIsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.transferTokens(IERC20(address(weth)), address(0), 10);
  }
}

contract CozyRouterWrapStEthSetup is CozyRouterTestSetup {
  uint256 forkId;

  function setUp() public virtual override {
    super.setUp();

    uint256 mainnetForkBlock = 15_770_305; // The mainnet block number at the time this test was written.
    forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), mainnetForkBlock);

    stEth = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    vm.label(address(stEth), "stETH");
    wstEth = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    vm.label(address(wstEth), "wstETH");

    // We need to redeploy the router because it's not on mainnet.
    router = new CozyRouter(
      manager,
      ICozyManager(address(0)),
      weth,
      stEth,
      wstEth,
      TriggerFactories({
        chainlinkTriggerFactory: chainlinkTriggerFactory,
        ownableTriggerFactory: ownableTriggerFactory,
        umaTriggerFactory: umaTriggerFactory
      }),
      IDripModelConstantFactory(address(9))
    );

    // Rather than redeploying *all* of Cozy Safety Module on mainnet for this fork test, we can get by with just this
    // mock safety module.
    safetyModule = ISafetyModule(address(0xBEEF));
    vm.mockCall(address(manager), abi.encodeWithSelector(manager.isSafetyModule.selector), abi.encode(true));
  }
}

contract CozyRouterWrapStEthTest is CozyRouterWrapStEthSetup {
  function testFork_WrapStEth1() public {
    _testWrapStEth(type(uint256).max, false);
  }

  function testFork_WrapStEth2() public {
    _testWrapStEth(100 ether, false);
  }

  function testFork_WrapStEth3() public {
    _testWrapStEth(20 ether, true);
  }

  function testFork_WrapStEthWithAmount1() public {
    _testWrapStEthWithAmount(10 ether, type(uint256).max, false);
  }

  function testFork_WrapStEthWithAmount2() public {
    _testWrapStEthWithAmount(10 ether, 10 ether, false);
  }

  function testFork_WrapStEthWithAmount3() public {
    _testWrapStEthWithAmount(10 ether, 20 ether, false);
  }

  function testFork_WrapStEthWithAmount4() public {
    _testWrapStEthWithAmount(10 ether, 2 ether, true);
  }

  function test_wstETHConstructorStEThAllowance() public {
    assertEq(stEth.allowance(address(router), address(router.wstEth())), type(uint256).max);
  }

  function _testWrapStEth(uint256 approvalAmount_, bool shouldRevert_) public {
    // deal(stETh, address, uint) won't work here because stETH is a proxy and deal isn't able to correctly infer the
    // storage location of the balance it needs to update.
    deal(address(this), 100 ether);
    stEth.submit{value: 100 ether}(address(42)); // Get some stETH.
    uint256 initStEthBalance_ = stEth.balanceOf(address(this));

    stEth.approve(address(router), approvalAmount_);

    if (shouldRevert_) vm.expectRevert();
    router.wrapStEth(address(safetyModule));
    if (shouldRevert_) return ();

    assertApproxEqAbs(wstEth.balanceOf(address(safetyModule)), stEth.getSharesByPooledEth(initStEthBalance_), 1);
  }

  function _testWrapStEthWithAmount(uint256 amount_, uint256 approvalAmount_, bool shouldRevert_) public {
    // deal(stETh, address, uint) won't work here because stETH is a proxy and deal isn't able to correctly infer the
    // storage location of the balance it needs to update.
    deal(address(this), 100 ether);
    stEth.submit{value: 100 ether}(address(42)); // Get some stETH.

    stEth.approve(address(router), approvalAmount_);
    if (shouldRevert_) vm.expectRevert();
    router.wrapStEth(address(safetyModule), amount_);
    if (shouldRevert_) return;

    uint256 wstEthAmount_ = stEth.getSharesByPooledEth(amount_);
    assertApproxEqAbs(wstEth.balanceOf(address(safetyModule)), wstEthAmount_, 1);
  }
}

contract CozyRouterUnwrapStEthTest is CozyRouterWrapStEthSetup {
  function testFork_UnwrapStEth() public {
    uint256 wstETHAmount_ = 100 ether;
    deal(address(wstEth), address(router), wstETHAmount_);
    uint256 stETHAmount_ = stEth.getPooledEthByShares(wstETHAmount_);
    uint256 initBalance_ = stEth.balanceOf(address(this));

    router.unwrapStEth(address(this));

    assertApproxEqAbs(stEth.balanceOf(address(this)), initBalance_ + stETHAmount_, 1);
  }

  function test_UnwrapStEthRevertsIfRecipientIsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unwrapStEth(address(0));
  }
}

contract CozyRouterWrapWethTest is CozyRouterTestSetup {
  function test_wrapWethAllEthHeldByRouter() public {
    uint256 ethAmount_ = 1 ether;
    deal(address(router), ethAmount_); // Simulate sending eth to the router before wrapNativeToken.

    vm.prank(alice);
    _expectEmit();
    emit Transfer(address(router), address(safetyModule), ethAmount_);
    router.wrapNativeToken(address(safetyModule));
    assertEq(address(router).balance, 0);
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(weth.balanceOf(address(safetyModule)), ethAmount_);
  }

  function test_wrapWethSomeEthHeldByRouter() public {
    uint256 ethAmount_ = 1 ether;
    deal(address(router), ethAmount_); // Simulate sending eth to the router before wrapNativeToken.

    vm.prank(alice);
    _expectEmit();
    emit Transfer(address(router), address(safetyModule), ethAmount_ / 2);
    router.wrapNativeToken(address(safetyModule), ethAmount_ / 2);
    assertEq(address(router).balance, ethAmount_ / 2);
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(weth.balanceOf(address(safetyModule)), ethAmount_ / 2);
  }
}

contract CozyRouterUnwrapWethTest is CozyWEthHelperTest {
  function test_UnwrapsWeth() public {
    testFuzz_UnwrapsWeth(10 ether, 1 ether);
  }

  function testFuzz_UnwrapsWeth(uint128 depositAmount_, uint128 withdrawAmount_) public {
    dealAndDepositEth(depositAmount_);
    withdrawAmount_ = uint128(bound(withdrawAmount_, 0, depositAmount_));

    router.unwrapNativeToken(address(alice), withdrawAmount_);
    assertEq(weth.balanceOf(address(router)), depositAmount_ - withdrawAmount_);
    assertEq(alice.balance, withdrawAmount_);
  }

  function test_UnwrapsMaxWeth() public {
    testFuzz_UnwrapsMaxWeth(1 ether);
  }

  function testFuzz_UnwrapsMaxWeth(uint128 amount_) public {
    dealAndDepositEth(amount_);

    router.unwrapNativeToken(address(alice));
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(alice.balance, amount_);
  }

  function test_RespectsAmount() public {}
  function test_RespectsRecipient() public {}

  function test_UnwrapsWethRevertsIfRecipientIsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unwrapNativeToken(address(0));

    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unwrapNativeToken(address(0), 10);
  }
}

contract CozyRouterDepositTest is CozyRouterTestSetup {
  function _depositAssets(
    bool isReserveDeposit_,
    ISafetyModule safetyModule_,
    uint8 poolId_,
    address user_,
    uint256 assets_
  ) internal {
    vm.startPrank(user_);

    // Mint some WETH.
    vm.deal(user_, assets_);
    weth.deposit{value: assets_}();
    weth.approve(address(router), assets_);

    // Deposit WETH via the router.
    uint256 shares = router.depositReserveAssets(safetyModule_, poolId_, assets_, user_);
    // : router.depositRewardAssets(safetyModule_, poolId_, assets_, user_, assets_);

    vm.stopPrank();

    assertEq(weth.balanceOf(address(safetyModule_)), assets_);
    if (isReserveDeposit_) {
      ReservePool memory reservePool_ = getReservePool(safetyModule_, poolId_);
      assertEq(reservePool_.depositReceiptToken.balanceOf(user_), shares);
      assertEq(reservePool_.depositAmount, assets_);
    } else {
      // RewardPool memory rewardPool_ = getRewardPool(safetyModule_, poolId_);
      // assertEq(rewardPool_.depositToken.balanceOf(user_), shares);
      // assertEq(rewardPool_.undrippedRewards, assets_);
    }
  }

  function _depositReserveAssetsRevertsIfRecipientIsZeroAddress(
    bool isReserveDeposit_,
    ISafetyModule safetyModule_,
    uint8 poolId_
  ) internal {
    vm.startPrank(address(0xBEEF));

    // Deal some weth
    vm.deal(address(0xBEEF), 10);
    weth.deposit{value: 10}();
    weth.approve(address(router), 10);
    vm.expectRevert(Ownable.InvalidAddress.selector);

    if (isReserveDeposit_) router.depositReserveAssets(safetyModule_, poolId_, 10, address(0));
    // else router.depositRewardAssets(safetyModule_, poolId_, 10, address(0), 10);

    vm.stopPrank();

    vm.expectRevert(Ownable.InvalidAddress.selector);
    if (isReserveDeposit_) router.depositReserveAssetsWithoutTransfer(safetyModule_, poolId_, 10, address(0));
    // else router.depositRewardAssetsWithoutTransfer(safetyModule_, poolId_, 10, address(0), 10);
  }

  function testFuzz_DepositReserveAssets(address user_, uint256 assets_) public {
    vm.assume(user_ != address(0));
    vm.assume(user_ != address(safetyModule));
    assets_ = bound(assets_, 1, type(uint96).max);

    _depositAssets(true, safetyModule, wethReservePoolId, user_, assets_);
  }

  // function testFuzz_DepositRewardAssets(address user_, uint256 assets_) public {
  //   vm.assume(user_ != address(0));
  //   vm.assume(user_ != address(safetyModule));
  //   assets_ = bound(assets_, 1, type(uint96).max);

  //   _depositAssets(false, safetyModule, wethRewardPoolId, user_, assets_);
  // }

  function test_DepositReserveAssetsRevertsIfRecipientIsZeroAddress() public {
    _depositReserveAssetsRevertsIfRecipientIsZeroAddress(true, safetyModule, wethReservePoolId);
  }

  // function test_DepositRewardAssetsRevertsIfRecipientIsZeroAddress() public {
  //   _depositReserveAssetsRevertsIfRecipientIsZeroAddress(false, safetyModule, wethRewardPoolId);
  // }
}

// contract CozyRouterStakeTest is CozyRouterTestSetup {
//   function testFuzz_Stake(address user_, uint256 assets_) public {
//     vm.assume(user_ != address(0));
//     vm.assume(user_ != address(safetyModule));
//     assets_ = bound(assets_, 1, type(uint96).max);

//     vm.startPrank(user_);

//     // Mint some WETH.
//     vm.deal(user_, assets_);
//     weth.deposit{value: assets_}();
//     weth.approve(address(router), assets_);

//     // Deposit WETH via the router.
//     uint256 shares = router.stake(safetyModule, wethReservePoolId, assets_, user_, assets_);

//     vm.stopPrank();

//     assertEq(weth.balanceOf(address(safetyModule)), assets_);
//     ReservePool memory reservePool_ = getReservePool(safetyModule, wethReservePoolId);
//     assertEq(reservePool_.stkToken.balanceOf(user_), shares);
//     assertEq(reservePool_.stakeAmount, assets_);
//   }

//   function test_StakeIfRecipientIsZeroAddress() public {
//     vm.startPrank(address(0xBEEF));

//     // Deal some weth
//     vm.deal(address(0xBEEF), 10);
//     weth.deposit{value: 10}();
//     weth.approve(address(router), 10);

//     vm.expectRevert(Ownable.InvalidAddress.selector);
//     router.stake(safetyModule, wethReservePoolId, 10, address(0), 10);

//     vm.stopPrank();

//     vm.expectRevert(Ownable.InvalidAddress.selector);
//     router.stakeWithoutTransfer(safetyModule, wethReservePoolId, 10, address(0), 10);
//   }
// }

contract CozyRouterConnectorSetup is CozyRouterTestSetup {
  MockConnector mockConnector;
  MockERC20 baseAsset = new MockERC20("Mock Base Asset", "MOCKBASE", 6);
}

contract CozyRouterWrapBaseAssetViaConnectorAndDepositTest is CozyRouterConnectorSetup {
  function _testWrapBaseAssetViaConnectorForDeposit(
    bool isReserveDeposit_,
    MockConnector connector_,
    ISafetyModule safetyModule_,
    uint8 poolId_,
    uint256 wrappedAssetDepositAmount_,
    uint256 baseAssetsNeeded_,
    address owner_
  ) internal {
    // Deal owner sufficient base assets to deposit.
    deal(address(connector_.baseAsset()), owner_, baseAssetsNeeded_, true);

    vm.startPrank(owner_);
    // Owner has to approve the router to transfer the base assets.
    connector_.baseAsset().approve(address(router), baseAssetsNeeded_);
    uint256 ownerShares_ = router.wrapBaseAssetViaConnectorAndDepositReserveAssets(
      connector_, safetyModule_, poolId_, baseAssetsNeeded_, owner_
    );
    // : router.wrapBaseAssetViaConnectorAndDepositRewardAssets(
    //   connector_, safetyModule_, poolId_, baseAssetsNeeded_, owner_, 0
    // );
    vm.stopPrank();

    // All base assets needed should have been transferred away from Owner.
    assertEq(connector_.baseAsset().balanceOf(owner_), 0);
    // Wrapped assets should have been transferred to safety module.
    assertEq(connector_.wrappedAsset().balanceOf(address(safetyModule_)), wrappedAssetDepositAmount_);

    // Owner should have proper number of deposit tokens.
    IERC20 depositReceiptToken_ = getReservePool(safetyModule_, poolId_).depositReceiptToken;
    // : getRewardPool(safetyModule_, poolId_).depositToken;
    assertEq(depositReceiptToken_.balanceOf(owner_), ownerShares_);
    assertEq(depositReceiptToken_.balanceOf(owner_), wrappedAssetDepositAmount_); // 1:1 exchange rate for initial
      // deposit.
  }

  function test_wrapBaseAssetViaConnectorForReserveDeposit() public {
    mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(reserveAssetA)));
    uint256 wrappedAssetDepositAmount_ = 500;
    uint256 baseAssetsNeeded_ = 250; // assetsNeeded_ / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)
    _testWrapBaseAssetViaConnectorForDeposit(
      true, mockConnector, safetyModule, 0, wrappedAssetDepositAmount_, baseAssetsNeeded_, alice
    );
    ReservePool memory reservePool_ = getReservePool(safetyModule, 0);
    assertEq(reservePool_.depositAmount, wrappedAssetDepositAmount_);
  }

  // function test_wrapBaseAssetViaConnectorForRewardDeposit() public {
  //   mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(rewardAssetA)));
  //   uint256 wrappedAssetDepositAmount_ = 500;
  //   uint256 baseAssetsNeeded_ = 250; // assetsNeeded_ / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)
  //   _testWrapBaseAssetViaConnectorForDeposit(
  //     false, mockConnector, safetyModule, 1, wrappedAssetDepositAmount_, baseAssetsNeeded_, alice
  //   );

  //   RewardPool memory rewardPool_ = getRewardPool(safetyModule, 1);
  //   assertEq(rewardPool_.undrippedRewards, wrappedAssetDepositAmount_);
  // }
}

// contract CozyRouterWrapBaseAssetViaConnectorAndStakeTest is CozyRouterConnectorSetup {
//   function test_wrapBaseAssetViaConnectorForStake() public {
//     mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(reserveAssetA)));
//     uint256 wrappedAssetStakeAmount_ = 500;
//     uint256 baseAssetsNeeded_ = 250; // assetsNeeded_ / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)

//     // Deal owner sufficient base assets to stake.
//     deal(address(mockConnector.baseAsset()), alice, baseAssetsNeeded_, true);

//     vm.startPrank(alice);
//     // Owner has to approve the router to transfer the base assets.
//     mockConnector.baseAsset().approve(address(router), baseAssetsNeeded_);
//     uint256 ownerShares_ =
//       router.wrapBaseAssetViaConnectorAndStake(mockConnector, safetyModule, 0, baseAssetsNeeded_, alice, 0);
//     vm.stopPrank();

//     // All base assets needed should have been transferred away from Owner.
//     assertEq(mockConnector.baseAsset().balanceOf(alice), 0);
//     // Wrapped assets should have been transferred to safety module.
//     assertEq(mockConnector.wrappedAsset().balanceOf(address(safetyModule)), wrappedAssetStakeAmount_);

//     // Owner should have proper number of deposit tokens.
//     IERC20 stkToken_ = getReservePool(safetyModule, 0).stkToken;
//     assertEq(stkToken_.balanceOf(alice), ownerShares_);
//     assertEq(stkToken_.balanceOf(alice), wrappedAssetStakeAmount_); // 1:1 exchange rate for initial deposit.
//   }
// }

contract CozyRouterUnwrapWrappedAssetViaConnectorForWithdraw is CozyRouterConnectorSetup {
  MockERC20 wrappedAsset;

  function setUp() public override {
    super.setUp();
    mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(reserveAssetA)));
    wrappedAsset = MockERC20(address(reserveAssetA));
  }

  function test_UnwrapWrappedAssetViaConnector() public {
    uint256 assets_ = 500;
    uint256 baseAssets_ = 250; // assetsNeeded / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)

    // Deal connector the wrapped assets held as a result of calling: withdraw, redeem, cancel, sell, claim, payout.
    wrappedAsset.mint(address(mockConnector), assets_);
    uint256 initWrappedAssetSupply = wrappedAsset.totalSupply();
    // Deal connector the base assets it should receive from wrapped asset contract when it unwraps.
    deal(address(baseAsset), address(mockConnector), baseAssets_, true);

    vm.startPrank(alice);
    router.unwrapWrappedAssetViaConnector(mockConnector, assets_, alice);
    vm.stopPrank();

    // Alice should hold the relevant amount of base assets.
    assertEq(mockConnector.baseAsset().balanceOf(alice), baseAssets_);
    // Supply of wrapped assets should have decreased by the amount withdrawn.
    assertEq(wrappedAsset.totalSupply(), initWrappedAssetSupply - assets_);
  }

  function test_UnwrapWrappedAssetViaConnectorForWithdrawFullBalance() public {
    uint256 assets_ = 500;
    uint256 baseAssets_ = 250; // assetsNeeded / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)

    // Deal connector the wrapped assets held as a result of calling: withdraw, redeem, cancel, sell, claim, payout.
    wrappedAsset.mint(address(mockConnector), assets_);
    uint256 initWrappedAssetSupply = wrappedAsset.totalSupply();
    // Deal connector the base assets it should receive from wrapped asset contract when it unwraps.
    deal(address(baseAsset), address(mockConnector), baseAssets_, true);

    vm.startPrank(alice);
    router.unwrapWrappedAssetViaConnectorForWithdraw(mockConnector, alice);
    vm.stopPrank();

    // Alice should hold the relevant amount of base assets.
    assertEq(mockConnector.baseAsset().balanceOf(alice), baseAssets_);
    // Supply of wrapped assets should have decreased by the amount withdrawn.
    assertEq(wrappedAsset.totalSupply(), initWrappedAssetSupply - assets_);
  }

  function testFail_UnwrapWrappedAssetViaConnectorZeroAssets() public {
    vm.expectCall(address(mockConnector), abi.encodeCall(mockConnector.unwrapWrappedAsset, (alice, 0)));
    router.unwrapWrappedAssetViaConnector(mockConnector, 0, alice);
  }

  function testFail_UnwrapWrappedAssetViaConnectorForWithdrawFullBalanceZeroAssets() public {
    vm.mockCall(
      address(mockConnector),
      abi.encodeWithSelector(mockConnector.balanceOf.selector, address(mockConnector)),
      abi.encode(0)
    );
    vm.expectCall(address(mockConnector), abi.encodeCall(mockConnector.unwrapWrappedAsset, (alice, 0)));
    router.unwrapWrappedAssetViaConnectorForWithdraw(mockConnector, alice);
  }
}

contract CozyRouterWithdrawTest is CozyRouterTestSetup {
  function test_Withdraw() public {}
  function test_RespectsMinSharesOut() public {}

  function _testWithdrawRequiresAllowance(
    bool isReserveWithdraw_,
    ISafetyModule safetyModule_,
    uint8 poolId_,
    address user_,
    uint256 assets_
  ) internal {
    vm.startPrank(user_);

    // Mint some WETH and approve the router to move it.
    vm.deal(user_, assets_);
    weth.deposit{value: assets_}();
    weth.approve(address(router), assets_);

    // The router deposits assets on behalf of the user.
    uint256 preDepositBalance_ = weth.balanceOf(user_);
    uint256 depositReceiptTokens_ = router.depositReserveAssets(safetyModule_, poolId_, assets_, user_);
    // : router.depositRewardAssets(safetyModule_, poolId_, assets_, user_, assets_);
    uint256 postDepositBalance_ = weth.balanceOf(user_);
    assertGt(preDepositBalance_, postDepositBalance_);

    // Request WETH withdrawal via the router. This should fail because the user hasn't approved it.
    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    if (isReserveWithdraw_) router.withdrawReservePoolAssets(safetyModule_, poolId_, assets_, user_);
    // else router.withdrawRewardPoolAssets(safetyModule_, poolId_, assets_, user_, depositTokens_);

    IERC20 depositReceiptToken_ = getReservePool(safetyModule_, poolId_).depositReceiptToken;
    // : getRewardPool(safetyModule_, poolId_).depositToken;

    // Approve WETH withdrawal request, then router initiates it.
    depositReceiptToken_.approve(address(router), depositReceiptTokens_);
    if (isReserveWithdraw_) {
      router.withdrawReservePoolAssets(safetyModule_, poolId_, assets_, user_);

      // Fast-forward to end of delay period.
      skip(getDelays(safetyModule_).withdrawDelay);

      router.completeWithdraw(safetyModule_, 0);
    } else {
      // Withdrawal from rewwards is instant.
      // router.withdrawRewardPoolAssets(safetyModule_, poolId_, assets_, user_, depositTokens_);
    }
    vm.stopPrank();

    assertEq(weth.balanceOf(user_), preDepositBalance_);
  }

  function testFuzz_WithdrawFromReserveRequiresAllowance(address user_, uint256 assets_) public {
    vm.assume(user_ != address(0));
    vm.assume(user_ != address(safetyModule));
    vm.assume(user_ != address(router));
    assets_ = bound(assets_, 1, type(uint96).max);

    _testWithdrawRequiresAllowance(true, safetyModule, wethReservePoolId, user_, assets_);
  }

  // function testFuzz_WithdrawFromRewardsRequiresAllowance(address user_, uint256 assets_) public {
  //   vm.assume(user_ != address(0));
  //   vm.assume(user_ != address(safetyModule));
  //   vm.assume(user_ != address(router));
  //   assets_ = bound(assets_, 1, type(uint96).max);

  //   _testWithdrawRequiresAllowance(false, safetyModule, wethRewardPoolId, user_, assets_);
  // }

  function test_WithdrawRevertsIfReceiverIsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.withdrawReservePoolAssets(safetyModule, wethReservePoolId, 10, address(0));

    // vm.expectRevert(Ownable.InvalidAddress.selector);
    // router.withdrawRewardPoolAssets(safetyModule, wethRewardPoolId, 10, address(0), 10);
  }
}

contract CozyRouterRedeemTest is CozyRouterTestSetup {
  address testRedeemer = address(this);
  uint256 shares;

  function _setUpWethBalances(
    bool isReserveDeposit_,
    ISafetyModule safetyModule_,
    uint8 poolId_,
    uint256 initialAmount_
  ) internal {
    vm.startPrank(testRedeemer);
    // Mint some WETH and approve the router to move it.
    vm.deal(testRedeemer, initialAmount_);
    weth.deposit{value: initialAmount_}();
    // Grant full approval to the router.
    weth.approve(address(router), type(uint256).max);
    // Deposit assets.
    uint256 depositReceiptTokenAmount_ =
      router.depositReserveAssets(safetyModule_, poolId_, initialAmount_, testRedeemer);
    // : router.depositRewardAssets(safetyModule_, poolId_, initialAmount_, testRedeemer, initialAmount_);
    // Approve for test redemptions.
    IERC20 depositReceiptToken_ = getReservePool(safetyModule_, poolId_).depositReceiptToken;
    // : getRewardPool(safetyModule_, poolId_).depositToken;
    depositReceiptToken_.approve(address(router), depositReceiptTokenAmount_);
    vm.stopPrank();
  }

  function testFuzz_RedeemFromReservePool(uint256 assets_) public {
    vm.assume(assets_ > 0 && assets_ <= type(uint128).max);
    _setUpWethBalances(true, safetyModule, wethReservePoolId, assets_);
    (uint64 redemptionId_, uint256 actualAssets_) =
      router.redeemReservePoolDepositReceiptTokens(safetyModule, wethReservePoolId, assets_, testRedeemer);
    assertEq(actualAssets_, assets_);
    assertEq(redemptionId_, 0);
  }

  // function testFuzz_RedeemFromRewardPool(uint256 assets_) public {
  //   vm.assume(assets_ > 0 && assets_ <= type(uint128).max);
  //   _setUpWethBalances(false, safetyModule, wethRewardPoolId, assets_);
  //   uint256 actualAssets_ =
  //     router.redeemRewardPoolDepositTokens(safetyModule, wethRewardPoolId, assets_, testRedeemer, assets_);
  //   assertEq(actualAssets_, assets_);
  // }

  function test_RedeemRevertsIfReceiverIsZeroAddress() public {
    vm.expectRevert(CozyRouterCommon.InvalidAddress.selector);
    router.redeemReservePoolDepositReceiptTokens(safetyModule, wethReservePoolId, 100, address(0));

    // vm.expectRevert(CozyRouter.InvalidAddress.selector);
    // router.redeemRewardPoolDepositTokens(safetyModule, wethReservePoolId, 100, address(0), 101);
  }
}

// contract CozyRouterUnstakeTest is CozyRouterTestSetup {
//   address testStaker = address(this);
//   uint256 shares;

//   function _setUpWethBalances(ISafetyModule safetyModule_, uint8 reservePoolId_, uint256 initialAmount_) internal {
//     vm.startPrank(testStaker);
//     // Mint some WETH and approve the router to move it.
//     vm.deal(testStaker, initialAmount_);
//     weth.deposit{value: initialAmount_}();
//     // Grant full approval to the router.
//     weth.approve(address(router), type(uint256).max);
//     // Stake assets.
//     uint256 stkTokenAmount_ = router.stake(safetyModule_, reservePoolId_, initialAmount_, testStaker,
// initialAmount_);
//     // Approve for test redemptions.
//     IERC20 stkToken_ = getReservePool(safetyModule_, reservePoolId_).stkToken;
//     stkToken_.approve(address(router), stkTokenAmount_);
//     vm.stopPrank();
//   }

//   function testFuzz_Unstake(uint256 assets_) public {
//     vm.assume(assets_ > 0 && assets_ <= type(uint128).max);
//     _setUpWethBalances(safetyModule, wethReservePoolId, assets_);
//     (uint64 redemptionId_, uint256 actualAssets_) =
//       router.unstake(safetyModule, wethReservePoolId, assets_, testStaker, assets_);
//     assertEq(actualAssets_, assets_);
//     assertEq(redemptionId_, 0);
//   }

//   function test_UnstakeRevertsIfReceiverIsZeroAddress() public {
//     vm.expectRevert(CozyRouter.InvalidAddress.selector);
//     router.unstake(safetyModule, wethReservePoolId, 100, address(0), 101);
//   }
// }

// contract CozyRouterUnstakeAssetAmountTest is CozyRouterTestSetup {
//   function testFuzz_UnstakeRequiresAllowance(address user_, uint256 assets_) public {
//     vm.assume(user_ != address(0));
//     vm.assume(user_ != address(safetyModule));
//     vm.assume(user_ != address(router));
//     assets_ = bound(assets_, 1, type(uint96).max);

//     vm.startPrank(user_);

//     // Mint some WETH and approve the router to move it.
//     vm.deal(user_, assets_);
//     weth.deposit{value: assets_}();
//     weth.approve(address(router), assets_);

//     // The router stakes assets on behalf of the user.
//     uint256 preStakeBalance_ = weth.balanceOf(user_);
//     uint256 depositTokens_ = router.stake(safetyModule, wethReservePoolId, assets_, user_, assets_);
//     uint256 postStakeBalance_ = weth.balanceOf(user_);
//     assertGt(preStakeBalance_, postStakeBalance_);

//     // Request WETH unstake via the router. This should fail because the user hasn't approved it.
//     _expectPanic(PANIC_MATH_UNDEROVERFLOW);
//     router.unstakeAssetAmount(safetyModule, wethReservePoolId, assets_, user_, depositTokens_);

//     IERC20 stkToken_ = getReservePool(safetyModule, wethReservePoolId).stkToken;

//     // Approve WETH unstake request, then router initiates it.
//     stkToken_.approve(address(router), depositTokens_);
//     router.unstakeAssetAmount(safetyModule, wethReservePoolId, assets_, user_, depositTokens_);
//     // Fast-forward to end of delay period.
//     skip(getDelays(safetyModule).unstakeDelay);
//     router.completeUnstake(safetyModule, 0);

//     vm.stopPrank();

//     assertEq(weth.balanceOf(user_), preStakeBalance_);
//   }

//   function test_UnstakeAssetAmountRevertsIfReceiverIsZeroAddress() public {
//     vm.expectRevert(Ownable.InvalidAddress.selector);
//     router.unstakeAssetAmount(safetyModule, wethReservePoolId, 10, address(0), 10);
//   }
// }

contract CozyRouterCompleteWithdrawRedeemTest is CozyRouterTestSetup {
  uint256 poolAssetAmount = 10_000;
  address testOwner = alice;
  address receiver = bob;

  function setUp() public override {
    super.setUp();
    vm.startPrank(testOwner);

    // Mint some WETH and approve the router to move it.
    vm.deal(testOwner, poolAssetAmount);
    weth.deposit{value: poolAssetAmount}();
    weth.approve(address(router), type(uint256).max); // Grant full approval to the router.

    // The router deposits assets on behalf of alice.
    uint256 depositReceiptTokens_ =
      router.depositReserveAssets(safetyModule, wethReservePoolId, poolAssetAmount, testOwner);

    // Initiate a WETH withdrawal request from the reserve pool, with bob as the receiver. The router is pre-approved.
    getReservePool(safetyModule, wethReservePoolId).depositReceiptToken.approve(address(router), depositReceiptTokens_);
    router.withdrawReservePoolAssets(safetyModule, wethReservePoolId, poolAssetAmount, receiver);
    skip(getDelays(safetyModule).withdrawDelay);

    vm.stopPrank();
  }

  function completeWithdrawRedeem(bool useCompleteWithdraw) public {
    vm.startPrank(testOwner);

    // Complete withdrawal, the receiver specified when the withdrawal was signalled receives the assets.
    if (useCompleteWithdraw) router.completeWithdraw(safetyModule, 0);
    else router.completeRedemption(safetyModule, 0);

    vm.stopPrank();

    assertEq(weth.balanceOf(testOwner), 0);
    assertEq(weth.balanceOf(receiver), poolAssetAmount);
  }

  function test_CompleteWithdraw() public {
    completeWithdrawRedeem(true);
  }

  function test_completeRedemption() public {
    completeWithdrawRedeem(false);
  }
}

contract CozyRouterExcessPayment is CozyRouterTestSetup {
  uint256 constant START_ASSETS = 200 ether;
  address immutable receiverA = _randomAddress();
  address immutable receiverB = _randomAddress();

  function setUp() public override {
    super.setUp();

    // Mint some WETH and approve the router to move it.
    vm.deal(alice, START_ASSETS);
    vm.deal(bob, START_ASSETS);

    vm.prank(alice);
    weth.deposit{value: START_ASSETS - 1 ether}();
    vm.prank(bob);
    weth.deposit{value: START_ASSETS - 1 ether}();
  }

  function _testExcessAssetsCanBeSplitAmongstDeposits(bool isReserveDeposit_) public {
    vm.prank(alice);
    weth.transfer(address(safetyModule), 3 ether);

    uint8 poolId_ = isReserveDeposit_ ? wethReservePoolId : wethRewardPoolId;
    IERC20 depositReceiptToken_ = getReservePool(safetyModule, poolId_).depositReceiptToken;
    // : getRewardPool(safetyModule, poolId_).depositToken;

    // Anyone can do arbitrary deposit operations with the excess ether.
    if (isReserveDeposit_) {
      router.depositReserveAssetsWithoutTransfer(safetyModule, poolId_, 1 ether, receiverA);
      assertEq(depositReceiptToken_.balanceOf(receiverA), 1 ether);
      router.depositReserveAssetsWithoutTransfer(safetyModule, poolId_, 1 ether, receiverB);
      assertEq(depositReceiptToken_.balanceOf(receiverB), 1 ether);
      router.depositReserveAssetsWithoutTransfer(safetyModule, poolId_, 1 ether, bob);
      assertEq(depositReceiptToken_.balanceOf(bob), 1 ether);
    } else {
      // router.depositRewardAssetsWithoutTransfer(safetyModule, poolId_, 1 ether, receiverA, 0);
      // assertEq(depositToken_.balanceOf(receiverA), 1 ether);
      // router.depositRewardAssetsWithoutTransfer(safetyModule, poolId_, 1 ether, receiverB, 0);
      // assertEq(depositToken_.balanceOf(receiverB), 1 ether);
      // router.depositRewardAssetsWithoutTransfer(safetyModule, poolId_, 1 ether, bob, 0);
      // assertEq(depositToken_.balanceOf(bob), 1 ether);
    }

    uint256 poolAmount_ = getReservePool(safetyModule, poolId_).depositAmount;
    // : getRewardPool(safetyModule, poolId_).undrippedRewards;

    assertEq(weth.balanceOf(address(safetyModule)) - poolAmount_, 0);

    // Once the arbitrary assets are depleted, any deposit without excess assets should fail.
    vm.expectRevert();
    router.depositReserveAssetsWithoutTransfer(safetyModule, poolId_, 1 ether, bob);
  }

  function test_excessAssetsCanBeSplitAmongstReserveDeposits() public {
    _testExcessAssetsCanBeSplitAmongstDeposits(true);
  }

  // function test_excessAssetsCanBeSplitAmongstRewardDeposits() public {
  //   _testExcessAssetsCanBeSplitAmongstDeposits(false);
  // }
}

contract CozyRouterRewardsManagerTest is CozyRouterTestSetup {
  IERC20 mockRewardToken = IERC20(address(new MockERC20("Mock Reward Token", "MOCK", 6)));

  RewardsManagerFactory rmFactory;
  StkReceiptToken stkTokenLogic;
  IRewardsManager rmLogic;
  ICozyManager rmCozyManager;
  DripModelConstantFactory dripModelConstantFactory = new DripModelConstantFactory();

  IRewardsManager rewardsManager;

  uint16 wethStakePoolId;
  uint16 mockStakePoolId;
  uint8 mockReservePoolId;

  function setUp() public virtual override {
    super.setUp();

    uint256 nonce_ = vm.getNonce(address(this));
    IRewardsManager computedAddrRewardsManagerLogic_ = IRewardsManager(vm.computeCreateAddress(address(this), nonce_));
    IReceiptToken depositReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 2));
    IReceiptToken stkReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 3));
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(address(this), nonce_ + 4));
    ICozyManager computedAddrCozyManager_ = ICozyManager(vm.computeCreateAddress(address(this), nonce_ + 5));

    rmLogic = IRewardsManager(
      address(
        new RewardsManager(
          ICozyManager(computedAddrCozyManager_),
          computedAddrReceiptTokenFactory_,
          ALLOWED_NUM_STAKE_POOLS,
          ALLOWED_NUM_REWARD_POOLS
        )
      )
    );
    rmLogic.initialize(owner, pauser, new StakePoolConfig[](0), new RewardPoolConfig[](0));
    rmFactory = new RewardsManagerFactory(computedAddrCozyManager_, computedAddrRewardsManagerLogic_);

    depositReceiptTokenLogic = new ReceiptToken();
    stkTokenLogic = new StkReceiptToken();
    depositReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkTokenLogic.initialize(address(0), "", "", 0);
    receiptTokenFactory = new ReceiptTokenFactory(depositReceiptTokenLogic_, stkReceiptTokenLogic_);
    rmCozyManager = new CozyManager(owner, pauser, rmFactory);

    router = new CozyRouter(
      manager,
      rmCozyManager,
      weth,
      stEth,
      wstEth,
      TriggerFactories({
        chainlinkTriggerFactory: chainlinkTriggerFactory,
        ownableTriggerFactory: ownableTriggerFactory,
        umaTriggerFactory: umaTriggerFactory
      }),
      IDripModelConstantFactory(address(dripModelConstantFactory))
    );

    bytes32 baseSalt_ = _randomBytes32();
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](2);
    stakePoolConfigs_[0] = StakePoolConfig({
      asset: IERC20(safetyModule.reservePools(0).depositReceiptToken),
      rewardsWeight: uint16(MathConstants.ZOC)
    });
    stakePoolConfigs_[1] = StakePoolConfig({
      asset: IERC20(safetyModule.reservePools(wethReservePoolId).depositReceiptToken),
      rewardsWeight: 0
    });
    stakePoolConfigs_ = sortStakePoolConfigs(stakePoolConfigs_);
    if (stakePoolConfigs_[0].asset == IERC20(safetyModule.reservePools(wethReservePoolId).depositReceiptToken)) {
      wethStakePoolId = 0;
      mockStakePoolId = 1;
    } else {
      wethStakePoolId = 1;
      mockStakePoolId = 0;
    }

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] =
      RewardPoolConfig({asset: mockRewardToken, dripModel: IDripModel(address(new MockDripModel(1e18)))});
    rewardsManager = router.deployRewardsManager(owner, pauser, stakePoolConfigs_, rewardPoolConfigs_, baseSalt_);

    mockReservePoolId = wethReservePoolId == 0 ? 1 : 0;
  }

  function test_UnstakeStakeReceiptTokensAndRedeem() public {
    // Deposit some rewards.
    uint256 rewardAssetAmount_ = 5e6;
    MockERC20(address(mockRewardToken)).mint(address(this), 5e6);
    mockRewardToken.approve(address(router), 5e6);
    router.depositRewardAssets(rewardsManager, 0, rewardAssetAmount_);

    // Deposit reserve assets and stake.
    uint256 reserveAssetAmount_ = 10e6;
    MockERC20(address(reserveAssetA)).mint(address(this), 10e6);
    reserveAssetA.approve(address(router), 10e6);
    uint256 stakeReceiptTokenAmount_ = router.depositReserveAssetsAndStake(
      safetyModule, rewardsManager, mockReservePoolId, mockStakePoolId, reserveAssetAmount_, address(this)
    );

    // Skip time so the reward assets drip (100% drip rate per second).
    // Reserve fees also drip (50% drip rate per second).
    skip(1);

    // Unstake and redeem.
    address receiver_ = address(0xBEEF);
    rewardsManager.stakePools(mockStakePoolId).stkReceiptToken.approve(address(router), stakeReceiptTokenAmount_);
    assertEq(
      rewardsManager.stakePools(mockStakePoolId).stkReceiptToken.balanceOf(address(this)), stakeReceiptTokenAmount_
    );
    (uint64 redemptionId_,) = router.unstakeStakeReceiptTokensAndRedeem(
      safetyModule, rewardsManager, mockReservePoolId, mockStakePoolId, stakeReceiptTokenAmount_, receiver_
    );

    skip(2 days); // Withdraw delay.
    router.completeRedemption(safetyModule, redemptionId_);

    // 100% rewards drip.
    assertEq(mockRewardToken.balanceOf(receiver_), rewardAssetAmount_);
    // 50% fee drip.
    assertEq(reserveAssetA.balanceOf(receiver_), reserveAssetAmount_ / 2);
  }

  function test_UnstakeReserveAssetsAndWithdraw() public {
    // Deposit some rewards.
    uint256 rewardAssetAmount_ = 5e6;
    MockERC20(address(mockRewardToken)).mint(address(this), rewardAssetAmount_);
    mockRewardToken.approve(address(router), rewardAssetAmount_);
    router.depositRewardAssets(rewardsManager, 0, rewardAssetAmount_);

    // Deposit reserve assets and stake.
    uint256 reserveAssetAmount_ = 10e6;
    MockERC20(address(reserveAssetA)).mint(address(this), reserveAssetAmount_);
    reserveAssetA.approve(address(router), reserveAssetAmount_);
    uint256 stakeReceiptTokenAmount_ = router.depositReserveAssetsAndStake(
      safetyModule, rewardsManager, mockReservePoolId, mockStakePoolId, reserveAssetAmount_, address(this)
    );

    // Skip time so the reward assets drip (100% drip rate per second).
    // Reserve fees also drip (50% drip rate per second).
    skip(1);

    // Unstake and redeem.
    address receiver_ = address(0xBEEF);
    rewardsManager.stakePools(mockStakePoolId).stkReceiptToken.approve(address(router), stakeReceiptTokenAmount_);
    assertEq(
      rewardsManager.stakePools(mockStakePoolId).stkReceiptToken.balanceOf(address(this)), stakeReceiptTokenAmount_
    );
    (uint64 redemptionId_,) = router.unstakeReserveAssetsAndWithdraw(
      safetyModule, rewardsManager, mockReservePoolId, mockStakePoolId, reserveAssetAmount_ / 2, receiver_
    );

    skip(2 days); // Withdraw delay.
    router.completeRedemption(safetyModule, redemptionId_);

    // 100% rewards drip.
    assertEq(mockRewardToken.balanceOf(receiver_), rewardAssetAmount_);
    // 50% fee drip.
    assertEq(reserveAssetA.balanceOf(receiver_), reserveAssetAmount_ / 2);
  }

  function test_UnstakeStakeReceiptTokensAndRedeem_RevertsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unstakeStakeReceiptTokensAndRedeem(safetyModule, rewardsManager, 0, mockStakePoolId, 10, address(0));
  }

  function test_UnstakeReserveAssetsAndWithdrawReceiver_RevertsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unstakeReserveAssetsAndWithdraw(safetyModule, rewardsManager, 0, mockStakePoolId, 10, address(0));
  }

  function test_WrapNativeTokenAndDepositReserveAssetsWithoutTransferAndStake() public {
    uint256 nativeTokenAmount_ = 10e6;
    deal(address(router), nativeTokenAmount_); // Simulate sending native tokens to the router before wrapNativeToken.

    _expectEmit();
    emit Transfer(address(router), address(safetyModule), nativeTokenAmount_);
    router.wrapNativeToken(address(safetyModule));
    assertEq(address(router).balance, 0);
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(weth.balanceOf(address(safetyModule)), nativeTokenAmount_);

    uint256 stakeReceiptTokenAmount_ = router.depositReserveAssetsWithoutTransferAndStake(
      safetyModule, rewardsManager, wethReservePoolId, wethStakePoolId, nativeTokenAmount_, address(this)
    );
    assertEq(stakeReceiptTokenAmount_, nativeTokenAmount_);
  }
}

contract CozyRouterDeploymentHelpersTest is CozyRouterTestSetup {
  IERC20 mockToken = IERC20(address(new MockERC20("Mock UMA Reward Token", "MOCK", 6)));

  RewardsManagerFactory rmFactory;
  StkReceiptToken stkTokenLogic;
  IRewardsManager rmLogic;
  ICozyManager rmCozyManager;
  DripModelConstantFactory dripModelConstantFactory = new DripModelConstantFactory();

  function setUp() public virtual override {
    super.setUp();
    uint256 nonce_ = vm.getNonce(address(this));
    IRewardsManager computedAddrRewardsManagerLogic_ = IRewardsManager(vm.computeCreateAddress(address(this), nonce_));
    IReceiptToken depositReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 2));
    IReceiptToken stkReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 3));
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(address(this), nonce_ + 4));
    ICozyManager computedAddrCozyManager_ = ICozyManager(vm.computeCreateAddress(address(this), nonce_ + 5));

    rmLogic = IRewardsManager(
      address(
        new RewardsManager(
          ICozyManager(computedAddrCozyManager_),
          computedAddrReceiptTokenFactory_,
          ALLOWED_NUM_STAKE_POOLS,
          ALLOWED_NUM_REWARD_POOLS
        )
      )
    );
    rmLogic.initialize(owner, pauser, new StakePoolConfig[](0), new RewardPoolConfig[](0));
    rmFactory = new RewardsManagerFactory(computedAddrCozyManager_, computedAddrRewardsManagerLogic_);

    depositReceiptTokenLogic = new ReceiptToken();
    stkTokenLogic = new StkReceiptToken();
    depositReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkTokenLogic.initialize(address(0), "", "", 0);
    receiptTokenFactory = new ReceiptTokenFactory(depositReceiptTokenLogic_, stkReceiptTokenLogic_);
    rmCozyManager = new CozyManager(owner, pauser, rmFactory);

    router = new CozyRouter(
      manager,
      rmCozyManager,
      weth,
      stEth,
      wstEth,
      TriggerFactories({
        chainlinkTriggerFactory: chainlinkTriggerFactory,
        ownableTriggerFactory: ownableTriggerFactory,
        umaTriggerFactory: umaTriggerFactory
      }),
      IDripModelConstantFactory(address(dripModelConstantFactory))
    );
  }

  function test_deployChainlinkTrigger() public {
    AggregatorV3Interface truthOracle_ = AggregatorV3Interface(address(new MockChainlinkOracle(1e6, 6)));
    AggregatorV3Interface trackingOracle_ = AggregatorV3Interface(address(new MockChainlinkOracle(1e6, 6)));
    uint256 priceTolerance_ = 0.5e4;
    uint256 truthFrequencyTolerance_ = 1200;
    uint256 trackingFrequencyTolerance_ = 86_400;

    bytes32 configId_ = chainlinkTriggerFactory.triggerConfigId(
      truthOracle_, trackingOracle_, priceTolerance_, truthFrequencyTolerance_, trackingFrequencyTolerance_
    );
    uint256 triggerCount_ = chainlinkTriggerFactory.triggerCount(configId_);
    address expectedTriggerAddress_ = chainlinkTriggerFactory.computeTriggerAddress(
      truthOracle_,
      trackingOracle_,
      priceTolerance_,
      truthFrequencyTolerance_,
      trackingFrequencyTolerance_,
      triggerCount_
    );

    ITrigger trigger_ = router.deployChainlinkTrigger(
      truthOracle_,
      trackingOracle_,
      priceTolerance_, // priceTolerance.
      truthFrequencyTolerance_, // truthFrequencyTolerance.
      trackingFrequencyTolerance_, // trackingFrequencyTolerance
      TriggerMetadata(
        "Peg Protection Trigger",
        "A trigger that protects from something depegging",
        "https://via.placeholder.com/150",
        "$category: Peg"
      )
    );

    assertEq(address(trigger_), expectedTriggerAddress_);
  }

  function test_deployChainlinkFixedPriceTrigger() public {
    address expectedFixedPriceAggregatorAddress_ = chainlinkTriggerFactory.computeFixedPriceAggregatorAddress(1800e8, 8);
    ChainlinkTriggerParams memory fixedPriceChainlinkTriggerParams_ = ChainlinkTriggerParams(
      AggregatorV3Interface(expectedFixedPriceAggregatorAddress_),
      AggregatorV3Interface(address(new MockChainlinkOracle(1801e8, 8))),
      0.99e4,
      0,
      1200
    );
    address expectedFixedPriceChainlinkTriggerAddress_ = chainlinkTriggerFactory.computeTriggerAddress(
      fixedPriceChainlinkTriggerParams_.truthOracle,
      fixedPriceChainlinkTriggerParams_.trackingOracle,
      fixedPriceChainlinkTriggerParams_.priceTolerance,
      fixedPriceChainlinkTriggerParams_.truthFrequencyTolerance,
      fixedPriceChainlinkTriggerParams_.trackingFrequencyTolerance,
      0 // triggerCount - Zero triggers have been deployed with this exact config.
    );

    ITrigger fixedPriceTrigger = router.deployChainlinkFixedPriceTrigger(
      1800e8,
      8,
      fixedPriceChainlinkTriggerParams_.trackingOracle,
      fixedPriceChainlinkTriggerParams_.priceTolerance,
      fixedPriceChainlinkTriggerParams_.trackingFrequencyTolerance,
      TriggerMetadata(
        "Fixed Price Protection Trigger",
        "A trigger that protects from something depegging",
        "https://via.placeholder.com/150",
        "$category: Peg"
      )
    );
    assertEq(address(fixedPriceTrigger), address(expectedFixedPriceChainlinkTriggerAddress_));
  }

  function test_deployOwnableTrigger() public {
    address owner_ = _randomAddress();
    bytes32 baseSalt_ = _randomBytes32();
    address expectedTriggerAddress_ =
      ownableTriggerFactory.computeTriggerAddress(owner_, router.computeSalt(address(this), baseSalt_));
    ITrigger trigger_ = router.deployOwnableTrigger(
      owner_,
      TriggerMetadata(
        "Trigger Name",
        "A trigger that will toggle if Protocol is hacked",
        "https://via.placeholder.com/150",
        "$category: Protocol"
      ),
      baseSalt_
    );
    assertEq(address(trigger_), expectedTriggerAddress_);
    assertEq(Ownable(address(trigger_)).owner(), owner_);
  }

  function test_deployUMATrigger() public {
    string memory query = "Has Protocol been hacked?";
    uint256 rewardAmount_ = 10e6; // $10 USDC
    address refundRecipient_ = _randomAddress();
    uint256 bondAmount_ = 100e6; // $100 USDC
    uint256 proposalDisputeWindow_ = 604_800; // 1 week

    bytes32 configId_ = umaTriggerFactory.triggerConfigId(
      query, mockToken, rewardAmount_, refundRecipient_, bondAmount_, proposalDisputeWindow_
    );
    address expectedTriggerAddress_ = umaTriggerFactory.computeTriggerAddress(
      query, mockToken, rewardAmount_, refundRecipient_, bondAmount_, proposalDisputeWindow_
    );

    // Deal reward amount required for the UMA oracle and approve the router to spend it.
    deal(address(mockToken), address(this), 10e6);
    mockToken.approve(address(router), 10e6);

    ITrigger trigger_ = router.deployUMATrigger(
      query,
      mockToken,
      rewardAmount_,
      refundRecipient_,
      bondAmount_,
      proposalDisputeWindow_,
      TriggerMetadata(
        "Trigger Name",
        "A trigger that will toggle if Protocol is hacked",
        "https://via.placeholder.com/150",
        "$category: Protocol"
      )
    );

    assertEq(address(trigger_), expectedTriggerAddress_);
    assertEq(umaTriggerFactory.exists(configId_), true);
  }

  function test_aggregateDeployTriggersAndSafetyModule() public {
    OwnableTriggerParams memory ownableTriggerParams_ = OwnableTriggerParams(_randomAddress(), _randomBytes32());
    address triggerA_ = ownableTriggerFactory.computeTriggerAddress(
      ownableTriggerParams_.owner, router.computeSalt(address(this), ownableTriggerParams_.salt)
    );

    UMATriggerParams memory umaTriggerParams_ =
      UMATriggerParams("Has Protocol been hacked?", mockToken, 10e6, _randomAddress(), 100e6, 604_800);
    address triggerB_ = umaTriggerFactory.computeTriggerAddress(
      umaTriggerParams_.query,
      umaTriggerParams_.rewardToken,
      umaTriggerParams_.rewardAmount,
      umaTriggerParams_.refundRecipient,
      umaTriggerParams_.bondAmount,
      umaTriggerParams_.proposalDisputeWindow
    );
    deal(address(mockToken), address(this), 10e6);
    mockToken.approve(address(router), 10e6);

    ChainlinkTriggerParams memory chainlinkTriggerParams_ = ChainlinkTriggerParams(
      AggregatorV3Interface(address(new MockChainlinkOracle(1e8, 8))),
      AggregatorV3Interface(address(new MockChainlinkOracle(1e8, 8))),
      0.25e4,
      1200,
      86_400
    );
    address triggerC_ = chainlinkTriggerFactory.computeTriggerAddress(
      chainlinkTriggerParams_.truthOracle,
      chainlinkTriggerParams_.trackingOracle,
      chainlinkTriggerParams_.priceTolerance,
      chainlinkTriggerParams_.truthFrequencyTolerance,
      chainlinkTriggerParams_.trackingFrequencyTolerance,
      0 // triggerCount - Zero triggers have been deployed with this exact config.
    );

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig({maxSlashPercentage: 0, asset: reserveAssetA});
    Delays memory delaysConfig_ =
      Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});
    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](3);
    triggerConfig_[0] = TriggerConfig({trigger: ITrigger(triggerA_), payoutHandler: _randomAddress(), exists: true});
    triggerConfig_[1] = TriggerConfig({trigger: ITrigger(triggerB_), payoutHandler: _randomAddress(), exists: true});
    triggerConfig_[2] = TriggerConfig({trigger: ITrigger(triggerC_), payoutHandler: _randomAddress(), exists: true});

    UpdateConfigsCalldataParams memory updateConfigsParams_ =
      UpdateConfigsCalldataParams(reservePoolConfigs_, triggerConfig_, delaysConfig_);

    {
      bytes[] memory calls_ = new bytes[](4);
      calls_[0] = abi.encodeWithSelector(
        router.deployOwnableTrigger.selector,
        ownableTriggerParams_.owner,
        TriggerMetadata(
          "Trigger Name A",
          "A triggerA that will toggle if Protocol is hacked",
          "https://via.placeholder.com/150A",
          "$category: A"
        ),
        ownableTriggerParams_.salt
      );
      calls_[1] = abi.encodeWithSelector(
        router.deployUMATrigger.selector,
        umaTriggerParams_.query,
        umaTriggerParams_.rewardToken,
        umaTriggerParams_.rewardAmount,
        umaTriggerParams_.refundRecipient,
        umaTriggerParams_.bondAmount,
        umaTriggerParams_.proposalDisputeWindow,
        TriggerMetadata(
          "Trigger NameB",
          "A triggerB that will toggle if Protocol is hacked",
          "https://via.placeholder.com/150B",
          "$category: B"
        )
      );
      calls_[2] = abi.encodeWithSelector(
        router.deployChainlinkTrigger.selector,
        chainlinkTriggerParams_.truthOracle,
        chainlinkTriggerParams_.trackingOracle,
        chainlinkTriggerParams_.priceTolerance,
        chainlinkTriggerParams_.truthFrequencyTolerance,
        chainlinkTriggerParams_.trackingFrequencyTolerance,
        TriggerMetadata(
          "Peg Protection Trigger",
          "A trigger that protects from something depegging",
          "https://via.placeholder.com/150",
          "$category: Peg"
        )
      );
      calls_[3] = abi.encodeWithSelector(
        router.deploySafetyModule.selector,
        _randomAddress(), // Owner
        _randomAddress(), // Pauser
        updateConfigsParams_,
        _randomBytes32() // Salt
      );

      // If this doesn't revert, the batch of calls was successful.
      // We also pass some ETH to ensure it doesn't revert for batches that require ETH to be sent.
      deal(address(this), 1e18);
      router.aggregate(calls_);
    }
  }

  function test_updateSafetyModuleMetadata() public {
    MockMetadataRegistry registry_ = new MockMetadataRegistry(address(router));

    // Safety module owner must call the router function.
    vm.prank(safetyModule.owner());
    router.updateSafetyModuleMetadata(
      IMetadataRegistry(address(registry_)),
      address(safetyModule),
      IMetadataRegistry.Metadata("Safety Module", "A safety module", "https://via.placeholder.com/150", "")
    );

    vm.prank(_randomAddress());
    vm.expectRevert();
    router.updateSafetyModuleMetadata(
      IMetadataRegistry(address(registry_)),
      address(safetyModule),
      IMetadataRegistry.Metadata("Safety Module", "A safety module", "https://via.placeholder.com/150", "")
    );
  }

  function test_deployRewardsManager() public {
    bytes32 baseSalt_ = _randomBytes32();

    IERC20 asset_ = IERC20(address(new MockERC20("MockAsset", "MOCK", 18)));
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: asset_, rewardsWeight: uint16(MathConstants.ZOC)});
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: asset_, dripModel: IDripModel(address(new MockDripModel(1e18)))});

    address expectedRewardsManagerAddr_ =
      rmCozyManager.computeRewardsManagerAddress(address(router), router.computeSalt(address(this), baseSalt_));
    IRewardsManager rewardsManager_ =
      router.deployRewardsManager(owner, pauser, stakePoolConfigs_, rewardPoolConfigs_, baseSalt_);

    // Loosely validate.
    assertEq(address(rewardsManager_), expectedRewardsManagerAddr_);
    assertEq(rewardsManager_.owner(), owner);
    assertEq(rewardsManager_.pauser(), pauser);
  }

  function test_deployDripModelConstant() public {
    uint256 amountPerSecond_ = _randomUint256();
    bytes32 baseSalt_ = _randomBytes32();

    address expectedDripModelAddr_ = dripModelConstantFactory.computeAddress(
      address(router), owner, amountPerSecond_, router.computeSalt(address(this), baseSalt_)
    );

    IDripModel dripModel_ = router.deployDripModelConstant(owner, amountPerSecond_, baseSalt_);

    assertEq(address(dripModel_), expectedDripModelAddr_);
  }

  function test_aggregateDeployDripModelConstantAndRewardsManager() public {
    uint256 amountPerSecond_ = _randomUint256();
    bytes32 baseSalt_ = _randomBytes32();
    address expectedDripModelAddr_ = dripModelConstantFactory.computeAddress(
      address(router), owner, amountPerSecond_, router.computeSalt(address(this), baseSalt_)
    );

    IERC20 asset_ = IERC20(address(new MockERC20("MockAsset", "MOCK", 18)));
    StakePoolConfig[] memory stakePoolConfigs_ = new StakePoolConfig[](1);
    stakePoolConfigs_[0] = StakePoolConfig({asset: asset_, rewardsWeight: uint16(MathConstants.ZOC)});
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({asset: asset_, dripModel: IDripModel(expectedDripModelAddr_)});
    address expectedRewardsManagerAddr_ =
      rmCozyManager.computeRewardsManagerAddress(address(router), router.computeSalt(address(this), baseSalt_));

    {
      bytes[] memory calls_ = new bytes[](2);
      calls_[0] = abi.encodeWithSelector(router.deployDripModelConstant.selector, owner, amountPerSecond_, baseSalt_);
      calls_[1] = abi.encodeWithSelector(
        router.deployRewardsManager.selector, owner, pauser, stakePoolConfigs_, rewardPoolConfigs_, baseSalt_
      );

      // If this doesn't revert, the batch of calls was successful.
      // We also pass some ETH to ensure it doesn't revert for batches that require ETH to be sent.
      deal(address(this), 1e18);
      router.aggregate(calls_);
    }

    // Loosely validate.
    assertEq(DripModelConstant(expectedDripModelAddr_).owner(), owner);
    assertEq(RewardsManager(expectedRewardsManagerAddr_).owner(), owner);
  }
}

contract CozyRouterAvaxTest is MockDeployProtocol {
  uint256 forkId;

  CozyRouterAvax router;
  IWeth wavax; // WAVAX conforms to the same interface as WETH.
  ISafetyModule safetyModule;

  address alice = address(0xABCD);
  address bob = address(0xDCBA);
  address self = address(this);

  /// @dev Emitted by ERC20s when `amount` tokens are moved from `from` to `to`.
  event Transfer(address indexed from, address indexed to, uint256 amount);

  function setUp() public virtual override {
    super.setUp();

    // The AVAX C Chain block number at the time this test was written.
    forkId = vm.createSelectFork(vm.envString("AVAX_RPC_URL"), 44_902_119);

    wavax = IWeth(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    vm.label(address(wavax), "WAVAX");

    IChainlinkTriggerFactory chainlinkTriggerFactory_ = IChainlinkTriggerFactory(address(new ChainlinkTriggerFactory()));
    IOwnableTriggerFactory ownableTriggerFactory_ = IOwnableTriggerFactory(address(new OwnableTriggerFactory()));
    OptimisticOracleV2Interface umaOracle_ = OptimisticOracleV2Interface(address(new MockUMAOracle())); // Mock for
      // tests.
    IUMATriggerFactory umaTriggerFactory_ = IUMATriggerFactory(address(new UMATriggerFactory(umaOracle_)));

    // We need to redeploy the router because it's not on avax.
    router = new CozyRouterAvax(
      manager,
      ICozyManager(address(0)),
      wavax,
      TriggerFactories({
        chainlinkTriggerFactory: chainlinkTriggerFactory_,
        ownableTriggerFactory: ownableTriggerFactory_,
        umaTriggerFactory: umaTriggerFactory_
      }),
      IDripModelConstantFactory(address(9))
    );

    safetyModule = ISafetyModule(address(0xBEEF));
  }

  function test_wrapWavaxAllAvaxHeldByRouter() public {
    uint256 avaxAmount_ = 1 ether;
    deal(address(router), avaxAmount_); // Simulate sending avax to the router before wrapNativeToken.

    vm.prank(alice);
    _expectEmit();
    emit Transfer(address(router), address(safetyModule), avaxAmount_);
    router.wrapNativeToken(address(safetyModule));
    assertEq(address(router).balance, 0);
    assertEq(wavax.balanceOf(address(router)), 0);
    assertEq(wavax.balanceOf(address(safetyModule)), avaxAmount_);
  }

  function test_wrapWavaxSomeAvaxHeldByRouter() public {
    uint256 avaxAmount_ = 1 ether;
    deal(address(router), avaxAmount_); // Simulate sending avax to the router before wrapNativeToken.

    vm.prank(alice);
    _expectEmit();
    emit Transfer(address(router), address(safetyModule), avaxAmount_ / 2);
    router.wrapNativeToken(address(safetyModule), avaxAmount_ / 2);
    assertEq(address(router).balance, avaxAmount_ / 2);
    assertEq(wavax.balanceOf(address(router)), 0);
    assertEq(wavax.balanceOf(address(safetyModule)), avaxAmount_ / 2);
  }
}
