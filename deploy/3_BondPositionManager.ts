import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { getDeployedContract } from '../utils/contract'
import { AssetPool, CouponManager } from '../typechain'
import { hardhat } from '@wagmi/chains'
import {deployWithVerify} from "../utils/misc";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('BondPositionManager')) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const assetPool = await getDeployedContract<AssetPool>('AssetPool')

  const chainId = network.config.chainId || hardhat.id

  const baseURI = `https://coupon.finance/api/nft/chains/${chainId}/bonds/`
  const contractURI = `https://coupon.finance/api/nft/chains/${chainId}/bonds`

  const args = [couponManager.address, assetPool.address, baseURI, contractURI]
  await deployWithVerify(hre, 'BondPositionManager', args)
}

deployFunction.tags = ['3']
deployFunction.dependencies = ['2']
export default deployFunction
