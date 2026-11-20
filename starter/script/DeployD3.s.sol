// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { TestToken } from "../src/TestToken.sol";
import { Xfers } from "../src/Xfers.sol";

/// D3 部署顺序：
///   ① Sepolia 部署测试代币   → DeployTestToken
///   ② Lasna 部署监控合约     → DeployXfers（带 lREACT 预付款，构造函数自动订阅）
///   ③ Sepolia 制造转账        → TriggerTransfer（mint + transfer）
///   ④ 等 10–60 秒，查 lastReactBlock / Turnover 事件

/// ① Sepolia：部署测试代币
///  forge script script/DeployD3.s.sol:DeployTestToken --rpc-url $SEPOLIA_RPC_URL --broadcast
contract DeployTestToken is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        TestToken t = new TestToken();
        vm.stopBroadcast();
        console.log("TOKEN_ADDR=", address(t));
    }
}

/// ② Lasna：部署监控合约（带 lREACT 预付款）
///  forge script script/DeployD3.s.sol:DeployXfers --rpc-url $LASNA_RPC_URL --broadcast
contract DeployXfers is Script {
    function run() external {
        address token = vm.envAddress("TOKEN_ADDR");
        uint256 minValue = vm.envOr("MIN_VALUE", uint256(100));
        uint256 limit = vm.envOr("D3_LIMIT", uint256(3));
        uint256 fund = vm.envOr("D3_FUND", uint256(0.5 ether)); // lREACT

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        Xfers x = new Xfers{ value: fund }(token, minValue, limit);
        vm.stopBroadcast();
        console.log("XFERS_ADDR=", address(x));
    }
}

/// ③ Sepolia：mint 然后 transfer，制造一笔超过阈值的 Transfer
///  forge script script/DeployD3.s.sol:TriggerTransfer --rpc-url $SEPOLIA_RPC_URL --broadcast
contract TriggerTransfer is Script {
    function run() external {
        address token = vm.envAddress("TOKEN_ADDR");
        address me = vm.addr(vm.envUint("PRIVATE_KEY"));
        address to = vm.envOr("TO_ADDR", address(0x000000000000000000000000000000000000dEaD));
        uint256 amount = vm.envOr("XFER_AMOUNT", uint256(500));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        TestToken(token).mint(me, amount);
        require(TestToken(token).transfer(to, amount), "transfer failed");
        vm.stopBroadcast();
        console.log("minted + transfered", amount);
    }
}
