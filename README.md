# InfoChain Protocol 🧠⛓️

> A cryptoeconomic architecture for verifiable information value & decentralized forecasting

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://foundry.paradigm.xyz)
[![Python 3.11+](https://img.shields.io/badge/Python-3.11+-blue.svg)](https://python.org)

## 🎯 Overview

InfoChain quantifies and settles **information value** on-chain using:
- **Proper scoring rules** (Brier, Logarithmic) for truthful forecasting incentives
- **Value of Information (VoI)** scaling rewards to network uncertainty
- **Zero-knowledge verification** for trustless off-chain computation
- **Merkle-optimized distribution** for gas-efficient reward claims

## 🚀 Quick Start

### Option A: Docker (Zero Setup)
```bash
# Clone & start
git clone https://github.com/yourorg/infochain.git
cd infochain
docker-compose up -d

# Run scoring engine inside container
docker-compose exec app python3 offchain/scoring_engine.py

# Access local node: http://localhost:8545