import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CLOBER_FACTORY, REPAY_ROUTER, TOKENS, WRAPPED1155_FACTORY } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { CouponManager, LoanPositionManager } from '../typechain'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if (await deployments.getOrNull('OdosRepayAdapter')) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const loanManager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')

  const chainId = network.config.chainId || hardhat.id

  await deploy('OdosRepayAdapter', {
    from: deployer,
    args: [
      WRAPPED1155_FACTORY[chainId],
      CLOBER_FACTORY[chainId],
      couponManager.address,
      TOKENS[chainId].WETH,
      loanManager.address,
      REPAY_ROUTER[chainId],
    ],
    log: true,
  })
}

deployFunction.tags = ['7']
deployFunction.dependencies = ['6']
export default deployFunction
