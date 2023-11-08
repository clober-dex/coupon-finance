import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { LIQUIDATOR_ROUTER, TOKENS } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { LoanPositionManager } from '../typechain'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if (await deployments.getOrNull('CouponLiquidator')) {
    return
  }

  const loanManager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')

  const chainId = network.config.chainId || hardhat.id

  await deploy('CouponLiquidator', {
    from: deployer,
    args: [loanManager.address, LIQUIDATOR_ROUTER[chainId], TOKENS[chainId].WETH],
    log: true,
  })
}

deployFunction.tags = ['9']
deployFunction.dependencies = ['8']
export default deployFunction
