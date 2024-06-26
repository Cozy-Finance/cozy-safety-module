// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";
import {ISafetyModuleFactory} from "../../src/interfaces/ISafetyModuleFactory.sol";
import {ICozySafetyModuleManager} from "../../src/interfaces/ICozySafetyModuleManager.sol";
import {IWeth} from "../../src/interfaces/IWeth.sol";
import {CozySafetyModuleManager} from "../../src/CozySafetyModuleManager.sol";
import {SafetyModule} from "../../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../../src/SafetyModuleFactory.sol";
import {ReservePoolConfig, UpdateConfigsCalldataParams} from "../../src/lib/structs/Configs.sol";
import {Delays} from "../../src/lib/structs/Delays.sol";
import {TriggerConfig} from "../../src/lib/structs/Trigger.sol";
import {MockDripModel} from "./MockDripModel.sol";
import {TestBase} from "../utils/TestBase.sol";

contract MockDeployer is TestBase {
  CozySafetyModuleManager manager;
  SafetyModuleFactory safetyModuleFactory;
  ReceiptToken depositReceiptTokenLogic;
  ReceiptToken stkReceiptTokenLogic;
  ReceiptTokenFactory receiptTokenFactory;
  MockDripModel feeDripModel;
  ISafetyModule safetyModuleLogic;
  IWeth weth;

  address owner = address(this);
  address pauser = address(0xBEEF);

  uint256 constant DEFAULT_FEE_DRIP_MODEL_CONSTANT = 0.5e18;
  uint8 constant ALLOWED_RESERVE_POOLS = 200;

  function deployMockProtocol() public virtual {
    // WETH bytecode obtained using `cast code 0x42000.006 -c optimism`.
    vm.etch(
      0x4200000000000000000000000000000000000006,
      hex"6080604052600436106100bc5760003560e01c8063313ce56711610074578063a9059cbb1161004e578063a9059cbb146102cb578063d0e30db0146100bc578063dd62ed3e14610311576100bc565b8063313ce5671461024b57806370a082311461027657806395d89b41146102b6576100bc565b806318160ddd116100a557806318160ddd146101aa57806323b872dd146101d15780632e1a7d4d14610221576100bc565b806306fdde03146100c6578063095ea7b314610150575b6100c4610359565b005b3480156100d257600080fd5b506100db6103a8565b6040805160208082528351818301528351919283929083019185019080838360005b838110156101155781810151838201526020016100fd565b50505050905090810190601f1680156101425780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b34801561015c57600080fd5b506101966004803603604081101561017357600080fd5b5073ffffffffffffffffffffffffffffffffffffffff8135169060200135610454565b604080519115158252519081900360200190f35b3480156101b657600080fd5b506101bf6104c7565b60408051918252519081900360200190f35b3480156101dd57600080fd5b50610196600480360360608110156101f457600080fd5b5073ffffffffffffffffffffffffffffffffffffffff8135811691602081013590911690604001356104cb565b34801561022d57600080fd5b506100c46004803603602081101561024457600080fd5b503561066b565b34801561025757600080fd5b50610260610700565b6040805160ff9092168252519081900360200190f35b34801561028257600080fd5b506101bf6004803603602081101561029957600080fd5b503573ffffffffffffffffffffffffffffffffffffffff16610709565b3480156102c257600080fd5b506100db61071b565b3480156102d757600080fd5b50610196600480360360408110156102ee57600080fd5b5073ffffffffffffffffffffffffffffffffffffffff8135169060200135610793565b34801561031d57600080fd5b506101bf6004803603604081101561033457600080fd5b5073ffffffffffffffffffffffffffffffffffffffff813581169160200135166107a7565b33600081815260036020908152604091829020805434908101909155825190815291517fe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c9281900390910190a2565b6000805460408051602060026001851615610100027fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0190941693909304601f8101849004840282018401909252818152929183018282801561044c5780601f106104215761010080835404028352916020019161044c565b820191906000526020600020905b81548152906001019060200180831161042f57829003601f168201915b505050505081565b33600081815260046020908152604080832073ffffffffffffffffffffffffffffffffffffffff8716808552908352818420869055815186815291519394909390927f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925928290030190a350600192915050565b4790565b73ffffffffffffffffffffffffffffffffffffffff83166000908152600360205260408120548211156104fd57600080fd5b73ffffffffffffffffffffffffffffffffffffffff84163314801590610573575073ffffffffffffffffffffffffffffffffffffffff841660009081526004602090815260408083203384529091529020547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff14155b156105ed5773ffffffffffffffffffffffffffffffffffffffff841660009081526004602090815260408083203384529091529020548211156105b557600080fd5b73ffffffffffffffffffffffffffffffffffffffff841660009081526004602090815260408083203384529091529020805483900390555b73ffffffffffffffffffffffffffffffffffffffff808516600081815260036020908152604080832080548890039055938716808352918490208054870190558351868152935191937fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef929081900390910190a35060019392505050565b3360009081526003602052604090205481111561068757600080fd5b33600081815260036020526040808220805485900390555183156108fc0291849190818181858888f193505050501580156106c6573d6000803e3d6000fd5b5060408051828152905133917f7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65919081900360200190a250565b60025460ff1681565b60036020526000908152604090205481565b60018054604080516020600284861615610100027fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0190941693909304601f8101849004840282018401909252818152929183018282801561044c5780601f106104215761010080835404028352916020019161044c565b60006107a03384846104cb565b9392505050565b60046020908152600092835260408084209091529082529020548156fea265627a7a7231582091c18790e0cca5011d2518024840ee00fecc67e11f56fd746f2cf84d5b583e0064736f6c63430005110032"
    );
    weth = IWeth(0x4200000000000000000000000000000000000006);

    uint256 nonce_ = vm.getNonce(address(this));
    IDripModel computedAddrFeeDripModel_ = IDripModel(vm.computeCreateAddress(address(this), nonce_));
    ICozySafetyModuleManager computedAddrManager_ =
      ICozySafetyModuleManager(vm.computeCreateAddress(address(this), nonce_ + 1));
    ISafetyModule computedAddrSafetyModuleLogic_ = ISafetyModule(vm.computeCreateAddress(address(this), nonce_ + 2));
    ISafetyModuleFactory computedAddrSafetyModuleFactory_ =
      ISafetyModuleFactory(vm.computeCreateAddress(address(this), nonce_ + 3));
    IReceiptToken depositReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 4));
    IReceiptToken stkReceiptTokenLogic_ = IReceiptToken(vm.computeCreateAddress(address(this), nonce_ + 5));
    IReceiptTokenFactory computedAddrReceiptTokenFactory_ =
      IReceiptTokenFactory(vm.computeCreateAddress(address(this), nonce_ + 6));

    feeDripModel = new MockDripModel(DEFAULT_FEE_DRIP_MODEL_CONSTANT);
    manager = new CozySafetyModuleManager(
      owner, pauser, computedAddrSafetyModuleFactory_, computedAddrFeeDripModel_, ALLOWED_RESERVE_POOLS
    );

    safetyModuleLogic = ISafetyModule(address(new SafetyModule(computedAddrManager_, computedAddrReceiptTokenFactory_)));
    safetyModuleLogic.initialize(
      address(0),
      address(0),
      UpdateConfigsCalldataParams({
        reservePoolConfigs: new ReservePoolConfig[](0),
        triggerConfigUpdates: new TriggerConfig[](0),
        delaysConfig: Delays({configUpdateDelay: 0, configUpdateGracePeriod: 0, withdrawDelay: 0})
      })
    );
    safetyModuleFactory = new SafetyModuleFactory(computedAddrManager_, computedAddrSafetyModuleLogic_);

    depositReceiptTokenLogic = new ReceiptToken();
    stkReceiptTokenLogic = new ReceiptToken();
    depositReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkReceiptTokenLogic.initialize(address(0), "", "", 0);
    receiptTokenFactory = new ReceiptTokenFactory(depositReceiptTokenLogic_, stkReceiptTokenLogic_);
  }
}

contract MockDeployProtocol is MockDeployer {
  function setUp() public virtual {
    deployMockProtocol();
  }
}
