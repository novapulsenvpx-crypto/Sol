# Sol
# ðŸŒŸ NovaPulse Token (NVPX)
### *The World's First Triple-Force Bonding Curve Token*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Network: BSC](https://img.shields.io/badge/Network-BNB%20Smart%20Chain-F0B90B)](https://bscscan.com)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.19-363636)](https://soliditylang.org)
[![Status: Open Source](https://img.shields.io/badge/Status-Open%20Source-brightgreen)](https://github.com)
[![Ownership: Renounced](https://img.shields.io/badge/Ownership-Renounced-red)](https://bscscan.com)

---

## ðŸ“Œ What is NovaPulse?

**NovaPulse (NVPX)** is a fully autonomous, open-source BEP-20 token deployed on BNB Smart Chain. It is engineered with three independent mathematical forces that cause the token price to rise permanently with every single on-chain interaction â€” buys, sells, transfers, and burns alike.

Unlike traditional tokens that rely on speculation or marketing for price growth, NovaPulse's price appreciation is **mathematically guaranteed by the smart contract code itself** â€” code that is publicly verifiable, permanently immutable after launch, and owned by no one.

> *"The first token where even selling raises the price."*

---

## ðŸ”¢ Token Information

| Property | Value |
|---|---|
| **Token Name** | NovaPulse |
| **Symbol** | NVPX |
| **Decimals** | 18 |
| **Max Supply** | 21,000,000 NVPX (Hard Cap â€” Bitcoin-like) |
| **Mint Price** | 2 USDT = 1 NVPX |
| **Network** | BNB Smart Chain (BSC) Mainnet |
| **Standard** | BEP-20 |
| **License** | MIT (fully open source) |
| **Compiler** | Solidity ^0.8.19 |

---

## âš¡ Tokenomics

| Parameter | Value | Description |
|---|---|---|
| **Buy Fee** | 0% | Zero cost to enter |
| **Sell Fee** | 3% | Auto-swapped to USDT â†’ fee wallet |
| **Auto-Burn** | 1% | Every transfer, forever |
| **Referral L1** | 3% | Direct referrer reward (from buyer) |
| **Referral L2** | 1.5% | Indirect referrer reward (from buyer) |
| **Swap Threshold** | 20 NVPX | Minimum fee before auto-swap fires |
| **Default Referrer** | `0x131D15d8E58900c934E5C6BE2e9054062CCfB427` | Fallback if no referrer registered |

---

## ðŸ“ˆ The Triple-Force Price Model

NVPX uses a **3-Force Bonding Curve** â€” three independent mathematical forces that compound together to push the price upward on every single transaction:

```
nvpxPrice = floorPrice Ã— scarcityMultiplier Ã— demandMultiplier
```

### ðŸ¦ Force 1 â€” Treasury Floor Price
```
floorPrice = treasuryUSDT Ã· circulatingSupply
```
- All USDT paid during minting (2 USDT per token) is locked in the contract treasury
- Every burn removes tokens WITHOUT removing USDT
- Result: same USDT Ã· fewer tokens = **floor price rises automatically**

### ðŸ’Ž Force 2 â€” Scarcity Multiplier
```
scarcityMultiplier = MAX_SUPPLY Ã· circulatingSupply
```
- 1% of every transfer is permanently burned
- As supply shrinks, multiplier grows above 1Ã—
- When 50% is burned: automatic **2Ã— price boost** stacked on floor

### ðŸ“Š Force 3 â€” Demand Multiplier
```
demandMultiplier = 1 + (transferCount Ã· demandSensitivity)
```
- Every single transfer increments a permanent on-chain counter
- More network activity = higher multiplier = higher price
- Never resets â€” only ever climbs

---

## ðŸ“Š Price Projection Table

| Tokens Burned | Circulating | Floor Price | Scarcity | Combined Price | Return vs Entry |
|---|---|---|---|---|---|
| 0 (Launch) | 21,000,000 | $2.00 | 1.00Ã— | **$2.00** | Baseline |
| 1,000,000 | 20,000,000 | $2.10 | 1.05Ã— | **$2.205** | +10.25% |
| 3,000,000 | 18,000,000 | $2.33 | 1.167Ã— | **$2.72** | +36% |
| 5,000,000 | 16,000,000 | $2.625 | 1.3125Ã— | **$3.445** | +72% |
| 10,000,000 | 11,000,000 | $3.818 | 1.909Ã— | **$7.293** | +265% |
| 15,000,000 | 6,000,000 | $7.00 | 3.50Ã— | **$24.50** | +1,125% |
| 18,000,000 | 3,000,000 | $14.00 | 7.00Ã— | **$98.00** | +4,800% |

> *Figures exclude demand multiplier (additional upside). These are formula outputs based on the smart contract mathematics, not financial advice.*

---

## ðŸ‘¥ Referral System

NovaPulse includes a **2-level referral program** built directly into the smart contract. All rewards are funded from the buyer's purchase â€” zero new tokens minted.

### How It Works

```
Alice registers Bob as her referrer â†’ registerReferrer(Bob)
Alice buys 1,000 NVPX on PancakeSwap

Bob (Level 1 â€” 3%)  receives: 30 NVPX  â†’ automatically
Carol (Level 2 â€” 1.5%) receives: 15 NVPX â†’ automatically (if Bob has a referrer)
Auto-Burn (1%)           burns: 10 NVPX  â†’ permanently destroyed
Alice receives:                 945 NVPX â†’ net amount
```

### Referral Rules (Enforced by Smart Contract)

| Rule | Status |
|---|---|
| Rewards funded from buyer's purchase | âœ… Zero inflation |
| One-time permanent binding | âœ… Cannot be changed |
| No self-referral | ðŸš« Blocked by `require()` |
| No circular chains (Aâ†’Bâ†’A) | ðŸš« Blocked at registration |
| Referrer must hold NVPX | âœ… Enforced on-chain |
| Default referrer if none set | âœ… `0x131D15d8E58900c934E5C6BE2e9054062CCfB427` |
| DEX buys only trigger rewards | âœ… Not sells or transfers |

---

## ðŸ’¸ Sell Fee Auto-Swap

The 3% sell fee is collected in NVPX and **automatically swapped to USDT via PancakeSwap**, then sent directly to the project fee wallet â€” fully on-chain, no manual claiming.

```
User sells NVPX on PancakeSwap
    â†’ 3% fee collected in contract (NVPX)
    â†’ Accumulates until 20 NVPX threshold reached
    â†’ Contract calls PancakeSwap Router
    â†’ NVPX â†’ USDT swap executes automatically
    â†’ USDT sent directly to fee receiver wallet
```

**Protections built in:**
- Reentrancy guard prevents flash loan attacks
- Liquidity check â€” skips swap if pool has < 1,000 USDT
- 2% slippage tolerance
- Failed swap recovery â€” fees re-accumulate safely

---

## ðŸ” Security Features

| Feature | Implementation |
|---|---|
| **Reentrancy Guard** | Dedicated `ReentrancyGuard` contract + `swapping` bool lock |
| **Ownership Renounced** | `goLive()` permanently revokes all admin roles |
| **SafeMath** | Explicit overflow checks + Solidity 0.8.19 built-ins |
| **Hard Supply Cap** | `require()` enforces 21M limit â€” inviolable |
| **Anti-Referral Abuse** | Self-referral, circular chains blocked at code level |
| **Liquidity Check** | Reads pair reserves before every auto-swap |
| **Open Source** | MIT license, verified on BscScan |
| **Immutable Launch** | `launchTimestamp` + `ProjectLaunched` event on-chain forever |

---

## ðŸš€ goLive() â€” One-Click Launch

When the project is ready, the deployer calls `goLive()` â€” a single transaction that atomically:

```solidity
1. isLive = true              // All config locked forever
2. ownershipRenounced = true  // Deployer loses all rights
3. mintingClosed = true       // No more minting ever
4. DEFAULT_ADMIN_ROLE revoked // Wallet completely stripped
5. launchTimestamp = now      // Immutable public launch record
6. ProjectLaunched emitted    // Permanent on-chain announcement
```

**After `goLive()` â€” the contract is 100% autonomous. No one can change anything. Ever.**

---

## ðŸ“ Repository Contents

```
ðŸ“ novapulsenvpx-crypto / Sol
   â”œâ”€â”€ README.md                  â† This file
   â”œâ”€â”€ NovaPulse_NVPX_v6.sol     â† Main smart contract (MIT)
   â””â”€â”€ NovaPulse_dApp.html        â† Frontend dApp (10 wallet support)
```

---

## ðŸ› ï¸ Contract Architecture

```
NovaPulse (NVPX)
â”œâ”€â”€ IERC20                    Standard ERC-20 interface
â”œâ”€â”€ SafeMath                  Overflow-safe arithmetic
â”œâ”€â”€ ReentrancyGuard           Attack prevention
â”œâ”€â”€ AccessControl             Role-based permissions
â”œâ”€â”€ IPancakeRouter            DEX swap integration
â”œâ”€â”€ IPancakePair              Liquidity reserve reading
â””â”€â”€ IFeeReceiver              Optional fee callback
```

---

## ðŸŒ Supported Wallets (dApp)

The NovaPulse dApp supports all major decentralised wallets via universal EIP-1193:

| Wallet | Platform |
|---|---|
| TokenPocket | iOS / Android |
| Bitget Wallet | iOS / Android |
| Trust Wallet | iOS / Android |
| OKX Wallet | iOS / Android |
| SafePal | iOS / Android |
| Coin98 | iOS / Android |
| Math Wallet | iOS / Android |
| imToken | iOS / Android |
| Binance Web3 Wallet | iOS / Android |
| MetaMask | Browser Extension |

---

## âš™ï¸ Deployment Guide

### Prerequisites
- Node.js (optional) or Remix IDE (browser-based)
- MetaMask or any Web3 wallet with BNB for gas (~$10)

### Step 1 â€” Compile
```
1. Open remix.ethereum.org
2. Upload NovaPulse_NVPX_v6.sol
3. Compiler: v0.8.19
4. Optimization: 200 runs
5. Click Compile
```

### Step 2 â€” Deploy
```
Constructor argument:
_usdt: 0x55d398326f99059fF775485246999027B3197955
(BSC Mainnet USDT address)
```

### Step 3 â€” Post-Deployment Setup
```
1. setMainPair(pancakeswapLPAddress)
2. Verify contract on BscScan
3. Add initial liquidity on PancakeSwap
4. Update CTR address in NovaPulse_dApp.html
5. Host dApp on Netlify or GitHub Pages
6. Call goLive() â† final step, irreversible
```

---

## ðŸ”— Key Addresses

| Item | Address |
|---|---|
| **BSC USDT** | `0x55d398326f99059fF775485246999027B3197955` |
| **PancakeSwap Router** | `0x10ED43C718714eb63d5aA57B78B54704E256024E` |
| **Default Referrer** | `0x131D15d8E58900c934E5C6BE2e9054062CCfB427` |
| **Fee Receiver** | `0x9504F94B3aE36B84e4a4dFA03BD1851737acf5Ac` |

---

## ðŸ“œ License

This project is licensed under the **MIT License** â€” see the full license text below.

```
MIT License

Copyright (c) 2025 NovaPulse (NVPX)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## âš ï¸ Disclaimer

This smart contract and associated software are provided for informational and educational purposes. The price projection tables represent mathematical formula outputs based on the contract's bonding curve mechanics and are not financial advice. Cryptocurrency investments carry significant risk. Always conduct your own research before investing. Past mathematical projections do not guarantee future results.

---

<div align="center">

**NovaPulse (NVPX) â€” Built on Mathematics. Secured by Code. Owned by No One.**

*MIT License Â· Open Source Â· BNB Smart Chain Â· 21,000,000 Hard Cap*

</div>
