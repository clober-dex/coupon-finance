import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import { deployWithVerify, getDeployedAddress } from '../utils'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('BondPositionManager')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const baseURI = `https://coupon.finance/api/nft/chains/${chainId}/bonds/`
  const contractURI = `https://coupon.finance/api/nft/chains/${chainId}/bonds`

  const args = [await getDeployedAddress('CouponManager'), await getDeployedAddress('AssetPool'), baseURI, contractURI]
  await deployWithVerify(hre, 'BondPositionManager', args)
}

deployFunction.tags = ['3']
deployFunction.dependencies = ['2']
export default deployFunction
