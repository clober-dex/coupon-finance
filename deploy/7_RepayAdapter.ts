import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CLOBER_FACTORY, REPAY_ROUTER, TOKENS, WRAPPED1155_FACTORY } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { CouponManager, LoanPositionManager } from '../typechain'
import { deployWithVerify } from '../utils/misc'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('RepayAdapter')) {
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
    REPAY_ROUTER[chainId],
  ]
  await deployWithVerify(hre, 'RepayAdapter', args)
}

deployFunction.tags = ['7']
deployFunction.dependencies = ['6']
export default deployFunction