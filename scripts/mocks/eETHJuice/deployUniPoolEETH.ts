import { ethers } from "hardhat";
import { abi as IUniswapV3FactoryABI } from "@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3Factory.sol/IUniswapV3Factory.json";
import { readConfigs, writeConfigs } from "../../utils";

async function main() {
  const networkAddresses = readConfigs();
  const [deployer] = await ethers.getSigners();

  const addresses = networkAddresses["goerli"];
  const uniswapV3Factory = new ethers.Contract(
    addresses.uniswapv3Factory,
    IUniswapV3FactoryABI,
    deployer,
  );

  const fee = 3000;

  try {
    let res = await uniswapV3Factory.getPool(
      addresses.weth,
      addresses.eeth,
      fee,
    );

    if (res) {
      console.log("Pool already exists at ", res);
      addresses.uniswapV3WETHEETHPool = res;
      return;
    } else {
      let res = await uniswapV3Factory.createPool(
        addresses.weth,
        addresses.eeth,
        fee,
      );
      await ethers.provider.waitForTransaction(res.transaction_hash);
      addresses.uniswapV3WETHEETHPool = res;
    }
  } catch (error) {
    console.error("Error:", error);
  }
  networkAddresses["goerli"] = addresses;

  writeConfigs(networkAddresses);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
