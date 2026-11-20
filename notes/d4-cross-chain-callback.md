# D4 作业｜跨链回调三步走（源链 emit → react() → 目标链回调）

## 这个任务一句话

让 Sepolia 上的一笔 `ping()` 事件，自动触发 Lasna 上的 `react()`，再自动让目标链（也是 Sepolia）上的回调合约记一笔。要交的证据是**三笔链上交易** + **一次"直接调回调被拒绝"的失败实验**。

跟 D3 的区别：D3 只监控、不回调（两条链）；D4 是完整的三段接力（有目标链回调这一步）。

```
① 源链 CampOrigin.ping(500)  → emit Ping(事件)
        ↓ Reactive 节点匹配订阅
② Lasna CampReactive.react() → 判断 value>=100，请求回调
        ↓ Callback Proxy 投递
③ 目标链 CampCallback.onEvent() → count+1, emit Handled  ← 这就是回调证据
```

## 环境现状（已帮你准备好，2026-11-20 核对）

| 项 | 状态 |
|---|---|
| forge | 1.10.0 稳定版 ✅ |
| 本地测试 | `forge test` 8/8 通过 ✅ |
| Sepolia ETH | 0.289（够，部署+回调要 ~0.05）✅ |
| Lasna lREACT | 0.497 ✅ |
| Sepolia RPC | publicnode，连续 3 次正常 ✅ |
| Callback Proxy 地址 | `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4`（官方文档今日核对，正确）✅ |
| `REACTIVE_FUND` | 已从默认 0.5 调到 **0.4**（你余额 0.497 不够 0.5，会部署失败）✅ |

> 注：源链和目标链默认都用 Ethereum Sepolia（chainId 11155111），Reactive 侧用 Lasna。任务允许这样，最省事。

## 手动上链步骤（你自己执行，按顺序来）

**每次新开终端、每次改完 .env，都要先 `set -a; source .env; set +a` 重新加载。**

部署一个，填一个地址，别一次性全跑。

### ① 源链部署事件源（Sepolia）

```bash
cd D:/Work/AI/reactive-builder-camp/starter
set -a; source .env; set +a
forge script script/Deploy.s.sol:DeployOrigin --rpc-url $SEPOLIA_RPC_URL --broadcast
```
打印 `ORIGIN_ADDR=0x...` → 填进 `.env` 的 `ORIGIN_ADDR=` → **重新 source**。

### ② Lasna 部署 Reactive 合约（预付 0.4 lREACT）

```bash
forge script script/Deploy.s.sol:DeployReactive --rpc-url $LASNA_RPC_URL --broadcast
```
打印 `REACTIVE_ADDR=0x...` → 填进 `.env` → **重新 source**。

### ③ 目标链部署回调合约（带 0.02 ETH 付回调 gas）

```bash
forge script script/Deploy.s.sol:DeployCallback --rpc-url $SEPOLIA_RPC_URL --broadcast
```
打印 `CALLBACK_ADDR=0x...` → 填进 `.env` → **重新 source**。

### ④ 回 Lasna 绑定回调地址

```bash
forge script script/Deploy.s.sol:SetRecipient --rpc-url $LASNA_RPC_URL --broadcast
```
打印 `recipient set` 即可，没有地址要填。

### ⑤ 触发！(value=500 ≥ 阈值 100)

```bash
forge script script/Deploy.s.sol:Ping --rpc-url $SEPOLIA_RPC_URL --broadcast
```
这一步会产生**第 1 笔证据交易**（源链 Ping）。

### ⑥ 等 10–60 秒，核验三笔

```bash
bash script/verify.sh
```
会打印：源链 Ping 事件交易哈希、Lasna 的 `lastReactBlock`、目标链 `count` 和 `Handled` 事件交易哈希。把三笔哈希抄下来。

## 失败实验（任务硬性要求）

**目的**：证明回调合约不能被随便调用——只有 Callback Proxy 调它才生效。

用你的钱包**直接**调回调合约的 `onEvent()`（绕过 Proxy），应该被拒绝。命令：

```bash
set -a; source .env; set +a
cast send $CALLBACK_ADDR 'onEvent(address,uint256,uint256,uint256)' 0x0000000000000000000000000000000000000000 11155111 1 500 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

（第一个参数是 `address`，填 `0x000...000` 占位即可；这台交易**故意要失败**。）

预期结果：交易 **revert / status 0**，报错含 `CallbackNotAuthorized` 或 `NotAuthorized`。

**一句话解释为什么被拒**（提交要用）：
> 回调合约的 `onEvent()` 加了 `onlyServiceProvider` 修饰符，只允许本链 Callback Proxy 调用；钱包直接调用时 `msg.sender` 是钱包地址、不是 Proxy，所以被拒绝。

把这笔失败交易的链接（Etherscan 上能搜到）**或报错截图**作为提交证据。

## 三笔证据交易（验证脚本会打印，填进提交卡）

| # | 是什么 | 浏览器 |
|---|---|---|
| 1 | 源链 Ping 事件 | `https://sepolia.etherscan.io/tx/<ping的hash>` |
| 2 | Reactive 上的 react() | `https://lasna.reactscan.net/tx/<react的hash>` |
| 3 | 目标链回调 Handled | `https://sepolia.etherscan.io/tx/<回调的hash>` |

> 如果 verify.sh 没直接打印 react 那笔交易的 hash：用 `lastReactBlock` 去 Reactscan 按区块号找，或看 `REACTIVE_ADDR` 合约页的 Internal Transactions。
