### 📄 GitHub README for **LendFort Protocol**

# LendFort Protocol

**LendFort** is a decentralized lending aggregator and liquidation insurance protocol built on the Stacks blockchain. It empowers users to earn optimal yields from top DeFi lending pools while being protected against unexpected liquidations through a robust insurance mechanism.

> **Tagline**: _Secure Yields. Fortified Lending._

---

## 🚀 Features

- 🔄 **Lending Aggregator**  
  Automatically allocates user funds across multiple lending protocols to maximize yield.

- 🛡️ **Liquidation Insurance**  
  Stake into a pooled insurance fund and file claims for protection against eligible liquidation losses.

- ♻️ **Batch Compounding**  
  Save gas fees and boost APYs through optimized interest compounding.

- ⚖️ **Risk-Aware Rebalancing**  
  Allocation is weighted by lender performance and risk scores to optimize safety and returns.

- 📁 **On-Chain Claim Management**  
  Submit, track, and verify insurance claims directly on-chain.

---

## 🔗 Supported Lending Platforms
- ALEX Lend  
- Bitflow Lend  
- Velar Lend  
- Fast Pool  
- Trustless Lend  

---

## 🧠 Key Smart Contract Modules

### 🏦 Lending

- `deposit-for-lending(amount)` – Supply STX to be allocated across lenders  
- `withdraw-lending(amount)` – Redeem deposited principal  
- `compound-interest(lenders)` – Batch compound interest for given lenders  
- `auto-rebalance-lenders()` – Automatically adjust allocations based on updated risk/yield profiles  

### 🛡️ Insurance

- `stake-for-insurance(amount)` – Stake into the insurance pool  
- `unstake-insurance(amount)` – Withdraw from insurance pool  
- `file-insurance-claim(amount, type, lender, hash)` – Submit liquidation claim with proof  
- `process-insurance-claim(claim-id, approved)` – Admin approval/rejection of submitted claim  

### 🧰 Admin / Utilities

- `update-lender-rate(lender, rate)` – Update APY of a specific lender  
- `update-lender-risk-score(lender, score)` – Set risk profile of a lender  
- `emergency-pause()` – Emergency pause feature (to be expanded)

---

## 📊 On-Chain Data Maps

- `user-deposits`: User deposits for lending  
- `user-insurance-stakes`: STX staked for insurance  
- `lender-allocations`: Allocation %, lending rate, etc.  
- `insurance-claims`: All claim data including timestamps and evidence  
- `user-claim-history`: Recent claims filed by user  
- `batch-transactions`: Log of gas-saving batch compound operations  
- `lender-risk-scores`: Tracks lender-specific risk profiles (0–1000 basis points)

---

## 🤝 Contributing

We welcome contributions to LendFort. If you have proposals, fixes, or improvements:

1. Fork this repo
2. Create a new branch (`git checkout -b feature/your-feature`)
3. Commit and push
4. Open a pull request

---

> **Lend wisely. Grow safely. Fortify your future with LendFort.**
