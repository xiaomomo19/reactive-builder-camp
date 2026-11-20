// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title Xfers — 监控 Sepolia 上 ERC-20 Transfer（D3 作业版）
/// @notice 基于官方 omni 分支 Xfers 示例改写：
///         1. 只监控「一个指定代币」的单笔大额 Transfer（可通过 token_ 指定；填 address(0) 则监控全部代币）
///         2. 构造函数完成订阅，不关心的 topic 用 REACTIVE_IGNORE
///         3. react() 带 onlySystem
///         4. remaining 次数上限，减到 0 自动退订
///         5. 过滤一律用 return，不用 revert（revert 也要收费）
///         6. 纯监控版：不请求回调，只 emit Turnover 作为 react() 被调用的证据
contract Xfers is AbstractReactive {
    /// @notice 每笔符合条件的转账被 react() 捕获时发出，作为链上证据
    event Turnover(
        address indexed token_,
        uint256 indexed volume_,
        uint256 txHash_,
        uint256 total_
    );

    /// @notice ERC-20 Transfer 事件的 topic0 = keccak256("Transfer(address,address,uint256)")
    uint256 private constant ERC20_TRANSFER_TOPIC_0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @notice Sepolia chainId
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    address public immutable OWNER;
    /// @notice 要监控的代币地址；address(0) 表示监控所有 ERC-20
    address public immutable TOKEN;
    /// @notice 单笔金额阈值：只有 value >= minValue_ 才计数
    uint256 public immutable MIN_VALUE;
    /// @notice 剩余可处理次数，归零后自动退订
    uint256 public remaining;
    /// @notice 已累计的合格转账笔数
    uint256 public total;

    uint256 public lastTxHash;
    uint256 public lastReactBlock;

    modifier onlyOwner() {
        require(msg.sender == OWNER, "not owner");
        _;
    }

    /// @param token_    要监控的 ERC-20 地址；address(0) = 全部代币
    /// @param minValue_ 单笔金额阈值（最小计数金额）
    /// @param limit_    最多处理多少笔后自动退订
    constructor(address token_, uint256 minValue_, uint256 limit_) payable {
        OWNER = msg.sender;
        TOKEN = token_;
        MIN_VALUE = minValue_;
        remaining = limit_;
        _sub();
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        // 防御性过滤：chainId / 合约 / topic0 对不上就直接跳过
        // 用 return 不用 revert —— revert 照样收费
        if (log_.chainId != SEPOLIA_CHAIN_ID) return;
        if (TOKEN != address(0) && log_.contractAddress != TOKEN) return;
        if (log_.topic0 != ERC20_TRANSFER_TOPIC_0) return;
        if (remaining == 0) return;

        // 官方示例里用 opCode==3 判断 LOG3；Omni 下用 address+topic0 联合过滤更稳妥。
        // Transfer(address indexed from, address indexed to, uint256 value)
        // from/to 是 indexed → 在 topic1/topic2；value 非 indexed → 在 data
        if (log_.data.length < 32) return;
        uint256 value = abi.decode(log_.data, (uint256));

        // 「单笔超过 X 才计数」判断
        if (value < MIN_VALUE) return;

        lastTxHash = log_.txHash;
        lastReactBlock = block.number;
        total += 1;
        emit Turnover(log_.contractAddress, value, log_.txHash, total);

        unchecked { --remaining; }
        if (remaining == 0) {
            _unsub();
        }
    }

    /// @notice 订阅 ERC-20 Transfer，不关心的 topic 用通配符
    function _sub() internal {
        SYSTEM.subscribe(
            SEPOLIA_CHAIN_ID,
            TOKEN,
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice 退订（参数必须和订阅时完全一致）
    function _unsub() internal {
        SYSTEM.unsubscribe(
            SEPOLIA_CHAIN_ID,
            TOKEN,
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice 补费 + 重置次数：欠费（debt>0）会导致合约静默停止
    function topUp(uint256 limit_) external payable onlyOwner {
        remaining = limit_;
    }
}
