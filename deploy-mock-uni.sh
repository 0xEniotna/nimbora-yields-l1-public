#! /bin/bash
source .env

# Deploy UniswapPool
echo Deploy mock pool.
yarn hardhat run --network ${NETWORK} scripts/mocks/eETHJuice/deployUniPoolEETH.ts
echo

# Deploy UniswapPool
echo Add liquidity
yarn hardhat run --network ${NETWORK} scripts/mocks/eETHJuice/initAndAddLiq.ts
echo