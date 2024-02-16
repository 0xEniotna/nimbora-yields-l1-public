import { ethers } from "hardhat";
import { abi as INonfungiblePositionManagerABI } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as IPoolABI } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json"; // Import Pool ABI
import { readConfigs } from "../../utils";
import { Position, Pool } from "@uniswap/v3-sdk";
import { Token } from "@uniswap/sdk-core";

async function main() {
  const networkAddresses = readConfigs();
  const [deployer] = await ethers.getSigners();
  const balance0ETH = await ethers.provider.getBalance(deployer.address);
  console.log("User Address:", deployer.address);
  console.log("User Balance:", ethers.formatEther(balance0ETH));

  const addresses = networkAddresses["goerli"];

  const positionManagerAddress = addresses.nonfungiblePositionManager;
  const positionManager = new ethers.Contract(
    positionManagerAddress,
    INonfungiblePositionManagerABI,
    deployer,
  );

  const poolAddress = addresses.uniswapV3WETHEETHPool;
  const poolContract = new ethers.Contract(poolAddress, IPoolABI, deployer);

  const token0Contract = await ethers.getContractAt("WETH9", addresses.weth);
  const token1Contract = await ethers.getContractAt(
    "eEthMintable",
    addresses.eeth,
  );

  const initialAmountEETH = ethers.parseEther("100");
  const initialAmountWETH = ethers.parseEther("100");
  const fee = 3000;
  const priceRatio = 1.000001; // 1 WstETH = 1.1542 WETH
  const sqrtPrice = Math.sqrt(priceRatio);
  const sqrtPriceX96 =
    (BigInt(sqrtPrice * 10 ** 18) * BigInt(2) ** BigInt(96)) / BigInt(10 ** 18);

  const tickLower = -887220;
  const tickUpper = 887220;

  try {
    console.log("Minting tokens");
    // amount, account for weth
    // account, amount for eeth
    await token0Contract.mint(initialAmountWETH, deployer.address);
    await token1Contract.mint(deployer.address, initialAmountEETH);

    console.log("Approving tokens");
    await token0Contract.approve(
      addresses.nonfungiblePositionManager,
      initialAmountWETH,
    );
    await token1Contract.approve(
      addresses.nonfungiblePositionManager,
      initialAmountEETH,
    );

    const slot0 = await poolContract.slot0();
    const isPoolInitialized = slot0.sqrtPriceX96.toString() !== "0";

    if (!isPoolInitialized) {
      console.log("Initializing Pool");
      let res = await poolContract.initialize(sqrtPriceX96);
      await ethers.provider.waitForTransaction(res.transaction_hash);
    } else {
      console.log("Pool is already initialized, skipping initialization.");
    }

    console.log("Adding Liquidity");
    const mintParams = {
      token0: addresses.weth,
      token1: addresses.eeth,
      fee: fee,
      tickLower: tickLower,
      tickUpper: tickUpper,
      amount0Desired: initialAmountWETH,
      amount1Desired: initialAmountEETH,
      amount0Min: 10000,
      amount1Min: 0,
      recipient: deployer.address,
      deadline: Math.floor(Date.now() / 1000) + 60 * 20,
    };
    console.log("Minting LP position");
    await positionManager.mint(mintParams);
    console.log("Liquidity added successfully");
  } catch (error) {
    console.error("Error:", error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
