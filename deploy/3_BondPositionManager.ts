import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { arbitrum, hardhat } from '@wagmi/chains'
import { CHAINLINK_FEEDS, TOKENS } from '../utils/constants'
import { computeCreate1Address } from '../utils/misc'
import { BigNumber } from 'ethers'
import { getDeployedContract } from '../utils/contract'
import { AssetPool, CouponManager } from '../typechain'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if ((await deployments.getOrNull('BondPositionManager')) !== null) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const assetPool = await getDeployedContract<AssetPool>('AssetPool')

  const chainId: number = network.config.chainId || hardhat.id

  let baseURI: string
  if (chainId === arbitrum.id) {
    baseURI = 'BOND_BASE_URI'
  } else {
    throw new Error('Unsupported network')
  }

  await deploy('BondPositionManager', {
    from: deployer,
    args: [couponManager.address, assetPool.address, baseURI],
    log: true,
  })
}

deployFunction.tags = ['3']
deployFunction.dependencies = ['2']
export default deployFunction
