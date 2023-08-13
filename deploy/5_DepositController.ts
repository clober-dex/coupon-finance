import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CLOBER_FACTORY, TOKENS, WRAPPED1155_FACTORY } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { BondPositionManager, CouponManager } from '../typechain'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if ((await deployments.getOrNull('DepositController')) !== null) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const bondManager = await getDeployedContract<BondPositionManager>('BondPositionManager')

  const chainId = network.config.chainId || hardhat.id

  await deploy('DepositController', {
    from: deployer,
    args: [
      WRAPPED1155_FACTORY[chainId],
      CLOBER_FACTORY[chainId],
      couponManager.address,
      TOKENS[chainId].WETH,
      bondManager.address,
    ],
    log: true,
  })
}

deployFunction.tags = ['5']
deployFunction.dependencies = ['4']
export default deployFunction
