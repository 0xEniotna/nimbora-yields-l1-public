import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { readConfigs, writeConfigs } from "../../scripts/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;
  const network: string = hre.network.name;
  if (network != "goerli") {
    throw "eETH is a mock contract and should be deployed on testnet only";
  }

  const eeth = await deploy(`eeth`, {
    from: deployer,
    log: true,
    contract: "eEthMintable",
    args: [],
  });
  console.log(`eeth contract deployed to ${eeth.address}`);

  const configs = readConfigs();
  configs.goerli.eeth = eeth.address;
  writeConfigs(configs);
};
export default func;
func.tags = ["eeth"];
