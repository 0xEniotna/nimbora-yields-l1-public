import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { readConfigs, writeConfigs } from "../../../scripts/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configs = readConfigs();
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const { deploy, get } = deployments;
  const network: string = hre.network.name;
  const addresses = network == "mainnet" ? configs.mainnet : configs.goerli;

  const minReceivedAmountFactor = "999000000000000000";
  const fee = "3000";
  // const uniswapV3StrategyDeployment = await deploy("UniswapV3StrategyEETH", {
  //   from: deployer,
  //   log: true,
  //   contract: "UniswapV3StrategyEETH",
  //   proxy: {
  //     proxyContract: "OpenZeppelinTransparentProxy",
  //     execute: {
  //       init: {
  //         methodName: "initialize",
  //         args: [
  //           addresses.l1PoolingManager,
  //           addresses.weth,
  //           addresses.eeth,
  //           addresses.uniswapv3Router,
  //           addresses.uniswapv3Factory,
  //           addresses.eethPriceFeed,
  //           minReceivedAmountFactor,
  //           fee,
  //         ],
  //       },
  //     },
  //   },
  // });

  const uniswapV3StrategyDeployment = await deploy("UniswapV3StrategyEETH", {
    from: deployer,
    log: true,
    contract: "UniswapV3StrategyEETHPool",
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            addresses.l1PoolingManager,
            addresses.weth,
            addresses.eeth,
            addresses.uniswapv3Router,
            addresses.uniswapv3Factory,
            addresses.eethPriceFeed,
            minReceivedAmountFactor,
            fee,
          ],
        },
      },
    },
  });

  console.log(
    `Uniswap strategy eETHJuice deployed at ${uniswapV3StrategyDeployment.address}`,
  );
  addresses.eETHJuiceStrategy.underlying = addresses.weth;
  addresses.eETHJuiceStrategy.bridge = addresses.ethBridge;
  addresses.eETHJuiceStrategy.strategy = uniswapV3StrategyDeployment.address;
  configs[network] = addresses;

  writeConfigs(configs);
};

export default func;
func.tags = ["PoolingManager"];
