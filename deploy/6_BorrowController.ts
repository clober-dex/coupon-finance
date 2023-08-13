import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CLOBER_FACTORY, TOKENS, WRAPPED1155_FACTORY } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { CouponManager, LoanPositionManager } from '../typechain'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if ((await deployments.getOrNull('BorrowController')) !== null) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const loanManager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')

  const chainId = network.config.chainId || hardhat.id

  await deploy('BorrowController', {
    from: deployer,
    args: [
      WRAPPED1155_FACTORY[chainId],
      CLOBER_FACTORY[chainId],
      couponManager.address,
      TOKENS[chainId].WETH,
      loanManager.address,
    ],
    log: true,
  })
}

deployFunction.tags = ['6']
deployFunction.dependencies = ['5']
export default deployFunction
