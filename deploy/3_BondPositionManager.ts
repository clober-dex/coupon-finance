import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { getDeployedContract } from '../utils/contract'
import { AssetPool, CouponManager } from '../typechain'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if ((await deployments.getOrNull('BondPositionManager')) !== null) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const assetPool = await getDeployedContract<AssetPool>('AssetPool')

  const baseURI = 'BOND_BASE_URI'

  await deploy('BondPositionManager', {
    from: deployer,
    args: [couponManager.address, assetPool.address, baseURI],
    log: true,
  })
}

deployFunction.tags = ['3']
deployFunction.dependencies = ['2']
export default deployFunction
