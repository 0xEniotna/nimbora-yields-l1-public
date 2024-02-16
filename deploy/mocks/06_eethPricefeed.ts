import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { readConfigs, writeConfigs } from "../../scripts/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configs = readConfigs();

  const { deployments, getNamedAccounts } = hre;
  const network: string = hre.network.name;
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  if (network != "goerli") {
    throw "eETH is a mock contract and should be deployed on testnet only";
  }

  const addresses = configs.goerli;

  const eethPriceFeedDeployment = await deploy(`eethPriceFeed`, {
    from: deployer,
    log: true,
    contract: "MockV3Aggregator",
    args: [18, "999999990000000000"],
  });
  console.log(
    `eeth PriceFeed contract deployed to ${eethPriceFeedDeployment.address}`,
  );

  addresses.eethPriceFeed = eethPriceFeedDeployment.address;
  configs.goerli = addresses;
  writeConfigs(configs);
};
export default func;
func.tags = ["eethPriceFeedDeployment"];
