import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CLOBER_FACTORY, TOKENS, WRAPPED1155_FACTORY } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { BondPositionManager, CouponManager } from '../typechain'
import {deployWithVerify} from "../utils/misc";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('DepositController')) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const bondManager = await getDeployedContract<BondPositionManager>('BondPositionManager')

  const chainId = network.config.chainId || hardhat.id

  const args = [
    WRAPPED1155_FACTORY[chainId],
    CLOBER_FACTORY[chainId],
    couponManager.address,
    TOKENS[chainId].WETH,
    bondManager.address,
  ]
  await deployWithVerify(hre, 'DepositController', args)
}

deployFunction.tags = ['5']
deployFunction.dependencies = ['4']
export default deployFunction
