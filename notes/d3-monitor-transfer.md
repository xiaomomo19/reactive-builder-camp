# D3 作业｜监控 Sepolia 上的 ERC-20 转账

## 这个任务一句话

在 Lasna 部署一个"监控合约"，让它盯着 Sepolia 上的 ERC-20 `Transfer` 事件；一旦有人转账，且金额达到阈值，就触发一次 `react()`，在链上留下证据。

## 我给的方案（和官方示例有什么不同）

官方 omni 分支的 `Xfers.sol` 订阅的是 **Sepolia 上所有 ERC-20** 的转账（合约地址用 `address(0)` 通配符）。问题是 Sepolia 转账太频繁，几秒钟就能把次数上限耗光、把预付的 lREACT 烧完。

任务说明允许"只监控一个自己部署的测试代币，或加单笔超过 X 才计数"。所以我采用更可控的做法：

> 自己部署一枚测试币 → 只监控这一枚 → 加"单笔 ≥ 100 才计数"的阈值。

这样只有你自己能触发，想什么时候跑就什么时候跑，不会因为别人的转账把次数耗光。

## 新增/改动的文件

| 文件 | 作用 |
|---|---|
| `starter/src/Xfers.sol` | 监控合约（部署在 Lasna），基于官方示例改写 |
| `starter/src/TestToken.sol` | 极简 ERC-20 测试币（部署在 Sepolia），带公开 `mint` |
| `starter/script/DeployD3.s.sol` | 三步部署脚本 |
| `starter/.env.example` | 补了 D3 需要的环境变量 |

`Xfers.sol` 已满足任务全部硬性要求：
- 构造函数里 `_sub()` 完成订阅，不关心的 topic 用 `REACTIVE_IGNORE`
- `react()` 带 `onlySystem`
- `remaining` 次数上限，减到 0 自动 `_unsub()` 退订
- 所有过滤用 `return`，不用 `revert`
- 部署时用 `{ value: fund }` 预充 lREACT，避免欠费停摆

## 提交前先本地验证（不用测试币）

```bash
cd D:/Work/AI/reactive-builder-camp/starter
forge build          # 已在本机验证通过：Compiler run successful
```

## 推荐路线：Remix + MetaMask（纯网页，绕开坏 RPC）

命令行路线卡在公共 RPC 反复失败（publicnode TLS 断、drpc 免费版不支持 Sepolia、tenderly 断连、alchemy demo 429 限流）。改用 **Remix 网页 + MetaMask**，gas 由 MetaMask 用它内置节点估算，全程不碰那几个坏 RPC。四步全在浏览器完成：

### M1. Sepolia 部署测试币

1. 打开 `https://remix.ethereum.org`
2. 左侧文件栏点 `+`，新建 `TestToken.sol`，把 `starter/src/TestToken.sol` 的内容整段粘进去
3. 左侧点编译器图标（宝石）→ Compiler 选 `0.8.29`（或更高）→ 点 `Compile TestToken.sol`，出绿色对勾
4. 左侧点部署图标（以太坊标志）→ Environment 选 `Injected Provider - MetaMask` → MetaMask 弹窗点"连接"，确认网络是 **Sepolia**
5. Contract 选 `TestToken` → 点橙色 `Deploy` → MetaMask 确认交易
6. 成功后 "Deployed Contracts" 下出现 TestToken，点复制图标拿地址 = **TOKEN_ADDR**

> 这份 `TestToken.sol` 是把仓库版的两个 internal 函数内联进公开函数后的等价写法，功能完全一样，只是方便整段复制进 Remix。

### M2. MetaMask 添加 Lasna 网络

MetaMask → 网络下拉 → 添加网络 → 手动添加：

| 字段 | 值 |
|---|---|
| 网络名称 | Lasna |
| RPC URL | `https://lasna-rpc.rnk.dev/` |
| Chain ID | `5318007` |
| 货币符号 | REACT |

（Chain ID 和 RPC 见 `docs/cheatsheet.md`。）确认 Lasna 账户有约 0.5 lREACT，不够就按 cheatsheet 转 ETH 去 faucet 合约换。

### M3. Lasna 部署监控合约（构造函数自动订阅）

1. Remix 新建 `Xfers.sol`，但里面有 3 个 `@reactive` import，Remix 默认拉不到。两个办法：
   - **简单**：把 `AbstractReactive.sol`、`IReactive.sol`、`ISystemContract.sol` 三个依赖文件也在 Remix 里新建同样路径粘进去（内容在 `starter/lib/reactive-lib-omni/src/` 下）
   - **省事**：直接把 import 改成相对本地文件，并把用到的常量（`SYSTEM`、`REACTIVE_IGNORE`、`LogRecord`、`onlySystem` 修饰所需的判断）内联进来
2. 编译通过后，部署页 Contract 选 `Xfers`，Deploy 按钮旁填三个构造参数：

   | 参数 | 值 |
   |---|---|
   | token_ | 上一步的 TOKEN_ADDR |
   | minValue_ | `100` |
   | limit_ | `3` |

3. VALUE 字段填 `500000000000000000`（= 0.5 lREACT，wei 单位），这是部署时预充的 lREACT
4. 网络切到 **Lasna**，点 `Deploy` → MetaMask 确认
5. 成功后的地址 = **XFERS_ADDR**

> 若 Remix 依赖文件处理起来太麻烦，可退回命令行部署 Xfers（第 ② 步）——Lasna 那条 RPC（`lasna-rpc.rnk.dev`）是官方节点、之前查参数一直正常，坏的只是 Sepolia 的公共 RPC。

### M4. Sepolia 制造转账（触发 react）

1. MetaMask 切回 **Sepolia**，Remix 里选已部署的 `TestToken` 合约
2. 调 `mint`，参数填：to = 你的钱包地址，amount = `500`
3. 再调 `transfer`，参数填：to = 任意地址（如 `0x000000000000000000000000000000000000dEaD`），amount = `500`
4. 500 ≥ 100，符合阈值，会被监控合约捕获

### M5. 验证 react()（用浏览器，不用 cast）

打开 `https://lasna.reactscan.net/address/<XFERS_ADDR>`，看 Transactions / Logs 里有没有 `Turnover` 事件，有就说明 `react()` 被成功调用。复制那条交易链接作为提交物。

---

## 命令行路线：已换稳定版 forge（2026-11-20）

原 nightly `1.6.0-nightly` 已换成 **stable `1.10.0`**（foundryup 下载，Sigstore 校验通过），装在 `D:/DEV/.foundry/bin/`，与 PATH 对齐，直接生效。旧 nightly 二进制备份在 `D:/DEV/.foundry/bin/nightly-backup/`，可回滚。

- 装 foundryup：`curl -sSL --ssl-no-revoke https://foundry.paradigm.xyz | sh`（GitHub 下载通道需 `--ssl-no-revoke` 绕过 schannel 握手失败）
- 装稳定版：`FOUNDRY_DIR=/d/DEV/.foundry ./foundryup.exe --install stable`
- 换版后彩排（不广播、不花钱）正常：`forge script ...:DeployTestToken --rpc-url $SEPOLIA_RPC_URL -g 130` → `TOKEN_ADDR=0x41CC...EbA`、Compiler run successful
- publicnode / tenderly 节点当前均已恢复，区块高度一致

**诚实记录**：换版前两次判断（换节点、拉 gas 倍率）都未能解决"gas 给多少烧多少"的失败。真正让它成功的是**稳定版 + `--start-fresh`**：稳定版会检查 broadcast 完整性（nightly 不查），加上 `--start-fresh` 清掉之前失败留下的半截账本（有交易无收据 + `recovery.lock`）。证据：本次成功 gasUsed≈338万，比之前失败的 262万上限还高——说明此前失败根本不是 gas 估低，而是 nightly 在损坏的广播状态下重复广播导致错乱。

**✅ 2026-11-20 14:44 部署成功**：`forge script ...:DeployTestToken -g 200 --broadcast --start-fresh`，链上验证 status 0x1、合约地址 `0x41ccccf85cdc5385738f9083e027d5c81d6f7eba`、symbol=D3T、字节码已落地。接下来把这个地址填进 `.env` 的 `TOKEN_ADDR=`，继续第 ② 步 Lasna 部署 Xfers。

## 手动上链步骤（命令行备选，你自己执行）

先复制环境变量模板、填好私钥并加载：

```bash
cd D:/Work/AI/reactive-builder-camp/starter
cp .env.example .env
# 编辑 .env，填入 PRIVATE_KEY（测试专用钱包）
set -a; source .env; set +a
```

确认钱包里：Sepolia 有 ETH（部署+转账用），Lasna 有 lREACT（约 0.5，不够就按 cheatsheet 第 3 节转 ETH 去 faucet 合约换）。

### ① Sepolia 部署测试币

```bash
forge script script/DeployD3.s.sol:DeployTestToken --rpc-url $SEPOLIA_RPC_URL --broadcast
```
输出 `TOKEN_ADDR=0x...`，填进 `.env`，重新 `set -a; source .env; set +a`。

**常见坑：公共 RPC 低估 gas 导致部署失败**

如果看到 `❌ [Failed]` 和 `Error: Transaction Failure`，去 Etherscan 查那笔交易，若提示 `contract creation code storage out of gas`，说明 gas 上限刚好卡在估算值、存合约代码时不够了。这是公共 RPC 估算偏低，不是代码写错。解决办法：加 `-g 200` 把 gas 估算倍率从默认 130% 提到 200%，再跑一次：

```bash
forge script script/DeployD3.s.sol:DeployTestToken --rpc-url $SEPOLIA_RPC_URL -g 200 --broadcast
```

失败的那笔交易 gas 不退（验证者已经干活了），nonce 会 +1，但没有生成合约。等成功打印出 `TOKEN_ADDR=0x...` 再填 `.env`。

**如果加了 `-g 200` 还是 `status 0`、gas 100% 烧光**：这是公共 RPC 的 gas 估算错了（gasLimit 会被算成 523295 的 1.3/2 倍，但链上真实执行远超），不是代码问题。公共节点经常抽风（publicnode 会 TLS 断、drpc 免费版已不支持 Sepolia）。换一个稳定 RPC 再跑，实测可用的是：

```
SEPOLIA_RPC_URL=https://sepolia.gateway.tenderly.co
```

在 `.env` 里改成上面这行，重新 source，再跑一次部署即可。长期建议用自己的 Alchemy / Infura 链接。

### ② Lasna 部署监控合约（构造函数自动订阅）

```bash
forge script script/DeployD3.s.sol:DeployXfers --rpc-url $LASNA_RPC_URL --broadcast
```
输出 `XFERS_ADDR=0x...`，填进 `.env`，重新 source。这一步把 0.5 lREACT 预付进合约，并按 `MIN_VALUE=100`、`D3_LIMIT=3` 设好阈值和次数上限。

### ③ Sepolia 制造一笔转账（触发条件）

```bash
forge script script/DeployD3.s.sol:TriggerTransfer --rpc-url $SEPOLIA_RPC_URL --broadcast
```
脚本会先 `mint` 500 给自己，再转 500 到 `0x...dEaD`。500 ≥ 100，符合阈值。

### ④ 等 10–60 秒，验证 react() 真的跑了

```bash
# 看 react() 是否执行（lastReactBlock 不再是 0 就成功）
cast call -r https://lasna-rpc.rnk.dev/ $XFERS_ADDR 'lastReactBlock()(uint256)'

# 查剩余次数（应该是 2，从 3 减到 2）
cast call -r https://lasna-rpc.rnk.dev/ $XFERS_ADDR 'remaining()(uint256)'

# 查欠费（应为 0；>0 会静默停止）
cast call -r https://lasna-rpc.rnk.dev/ 0x8888888888888888888888888888888888888888 'debt(address)(uint256)' $XFERS_ADDR
```

## ✅ 三项提交物（已核验真实数据，2026-11-20 15:17）

链上实测状态：Xfers 合约 `0xd1792E3c4f0624320e9a50Feeed69d96a3C35c8D`、`total=2`、`remaining=1`、`lastReactBlock=8793350`，react() 成功触发 2 次。

**1. 监控合约地址（Reactscan）**
```
https://lasna.reactscan.net/address/0xd1792e3c4f0624320e9a50Feeed69d96a3C35c8D
```

**2. react() 被调用的交易链接**（二选一，均已核验 status=success 且发出 Turnover 事件）
```
https://lasna.reactscan.net/tx/0xce7b981ef1136a391cf5a99f1fc31c6431f9f2c0e8056b57234d5884c6774e49
（备用）https://lasna.reactscan.net/tx/0x1531e05ee3835aa6a636b743dd135266fd47f6243caa379d60e94ac212662df4
```
- 两笔都发出 `Turnover` 事件（topic0=0x786271f1…），token=测试币 D3T、value=500(0x1f4)。
- 第 2 笔（0xce7b…）的 data 里带 lastTxHash=0xebbd5ab2…，对应源链交易。

**3. 源链触发交易（Sepolia，加分项）**
```
https://sepolia.etherscan.io/tx/0xebbd5ab2ca6e411f264a19852fddb89d9d9c2016143563d4207cd7a22895709d
```
（status=success，区块 12173779）

**4. 过滤条件一句话**
只处理 Sepolia 链上指定测试代币（0x41CC…fEbA）的 ERC-20 Transfer 事件，且单笔金额 >= 100 才计数；累计 3 笔后自动退订，不满足条件的用 return 跳过（不 revert）。

---

## 三项提交物（旧模板，去浏览器复制真实链接）

1. **合约地址（Reactscan）**：`https://lasna.reactscan.net/address/<XFERS_ADDR>`
   - 在这个页面找 `react()` 被调用的那条交易（Transactions / Internal Transactions），点进去复制交易链接。
2. **一笔 react() 被调用的交易链接**：`https://lasna.reactscan.net/tx/<那笔交易的hash>`
   - 找不到时，用第 ④ 步查到的 `lastReactBlock`，去 Reactscan 按区块号找那条交易。
3. **过滤条件一句话**：见下方"提交文案"。

> Sepolia 上的触发交易链接（第 ③ 步）也一并附上，链路更完整：`https://sepolia.etherscan.io/tx/<transfer的hash>`

## 提交文案（可直接用）

```
D3 完成：在 Lasna 部署 Xfers 监控合约，订阅 Sepolia 上指定 ERC-20 的 Transfer 事件并成功触发 react()。

- 监控合约（Lasna/Reactscan）：https://lasna.reactscan.net/address/0xd1792E3c4f0624320e9a50Feeed69d96a3C35c8D
- react() 调用交易：https://lasna.reactscan.net/tx/0xce7b981ef1136a391cf5a99f1fc31c6431f9f2c0e8056b57234d5884c6774e49
- 源链触发交易（Sepolia）：https://sepolia.etherscan.io/tx/0xebbd5ab2ca6e411f264a19852fddb89d9d9c2016143563d4207cd7a22895709d

过滤条件：只处理 Sepolia 上指定测试代币（0x41CC…fEbA）的 Transfer 事件，且单笔金额 >= 100 才计数；累计处理 3 笔后自动退订，不满足条件的用 return 跳过（不 revert）。
```

## 自己提交（我不替你 commit/push）

```bash
cd D:/Work/AI/reactive-builder-camp
git add starter/src/Xfers.sol starter/src/TestToken.sol starter/script/DeployD3.s.sol starter/.env.example notes/d3-monitor-transfer.md
git status --short
git commit -m "Add D3 ERC-20 Transfer monitor with tested token and threshold filter"
git push origin main
```

注意：`.env` 已被 `.gitignore` 忽略，不会提交；确认 `git status` 里没有 `.env` 或私钥再 push。
