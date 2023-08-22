import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  if (await deployments.getOrNull('CouponOracle')) {
    return
  }

  await deploy('CouponOracle', {
    from: deployer,
    args: [],
    log: true,
  })
}

deployFunction.tags = ['0']
export default deployFunction
