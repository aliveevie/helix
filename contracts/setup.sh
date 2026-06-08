#!/usr/bin/env bash
# Fetch Helix contract dependencies (vendored via shallow clone, kept out of git).
# Run from the contracts/ directory:  ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p lib
cd lib

clone() { # repo dir
  if [ -d "$2" ]; then echo "✓ $2 already present"; else
    echo "→ cloning $2"; git clone --depth 1 "$1" "$2" >/dev/null 2>&1; fi
}

clone https://github.com/foundry-rs/forge-std.git                     forge-std
clone https://github.com/Uniswap/v4-core.git                          v4-core
clone https://github.com/Uniswap/v4-periphery.git                     v4-periphery
clone https://github.com/OpenZeppelin/openzeppelin-contracts.git      openzeppelin-contracts
clone https://github.com/transmissions11/solmate.git                  solmate

echo "Dependencies ready. Run: forge build && forge test"
