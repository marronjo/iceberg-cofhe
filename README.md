[![codecov](https://codecov.io/gh/marronjo/iceberg-cofhe/graph/badge.svg?token=K6XI2N7XOL)](https://codecov.io/gh/marronjo/iceberg-cofhe)

# 🧊☕ iceberg-cofhe

> **FHE Encrypted Limit Orders on Uniswap v4**

**iceberg-cofhe** introduces confidential, iceberg-style limit orders to Uniswap v4 using [Fully Homomorphic Encryption (FHE)](https://fhenix.io/) via the [Fhenix coprocessor](https://cofhe-docs.fhenix.zone/docs/devdocs/overview). Limit order data like trade size and direction are encrypted on-chain and privately stored in the Iceberg hook   
— enabling privacy-preserving DeFi trading.

🔒 Built with FHE  
🦄 Runs as a Uniswap v4 hook  
🚀 Enables private, on-chain limit orders  

## 🌊 How It Works

- Users place encrypted limit orders through the hook (`placeIcebergOrder`) by providing encrypted values:
  - `liquidity`: order size
  - `zeroForOne`: swap direction
- Orders are stored in a privacy-preserving mapping, protected by FHE.
- In the `afterSwap()` callback the hook evaluates encrypted order conditions without leaking user intent.
- Once matching conditions are met, decryption is securely requested to fill the order.
- In the next `beforeSwap()` callback, the decryption result is requested.
  - If the decryption is ready, the order is filled.
  - Otherwise, the swap lifecycle continues 

---

## 🛠 Setup & Installation

> Requires [Foundry](https://book.getfoundry.sh).

```bash
forge install
forge test
```
