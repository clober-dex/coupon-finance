import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CLOBER_FACTORY, TOKENS, WRAPPED1155_FACTORY } from '../utils/constants'
import { getDeployedContract } from '../utils/contract'
import { CouponManager, LoanPositionManager } from '../typechain'
import {deployWithVerify} from "../utils/misc";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('BorrowController')) {
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
  ]
  await deployWithVerify(hre, 'BorrowController', args)
}

deployFunction.tags = ['6']
deployFunction.dependencies = ['5']
export default deployFunction
