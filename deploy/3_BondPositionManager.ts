import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { getDeployedContract } from '../utils/contract'
import { AssetPool, CouponManager } from '../typechain'
import { hardhat } from '@wagmi/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if (await deployments.getOrNull('BondPositionManager')) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const assetPool = await getDeployedContract<AssetPool>('AssetPool')

  const chainId = network.config.chainId || hardhat.id

  const baseURI = `https://coupon.finance/api/nft/bond/${chainId}/`
  const contractURI = 'BOND_CONTRACT_URI'

  await deploy('BondPositionManager', {
    from: deployer,
    args: [couponManager.address, assetPool.address, baseURI, contractURI],
    log: true,
  })
}

deployFunction.tags = ['3']
deployFunction.dependencies = ['2']
export default deployFunction
