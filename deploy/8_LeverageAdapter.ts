import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CLOBER_FACTORY, LEVERAGE_ROUTER, TOKENS, WRAPPED1155_FACTORY } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { CouponManager, LoanPositionManager } from '../typechain'
import { deployWithVerify } from '../utils/misc'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('LeverageAdapter')) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const loanManager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBER_FACTORY[chainId],
    couponManager.address,
    TOKENS[chainId].WETH,
    loanManager.address,
    LEVERAGE_ROUTER[chainId],
  ]
  await deployWithVerify(hre, 'LeverageAdapter', args)
}

deployFunction.tags = ['8']
deployFunction.dependencies = ['7']
export default deployFunction
