import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { arbitrum, hardhat } from '@wagmi/chains'
import { CHAINLINK_FEEDS, TOKENS, TREASURY } from '../utils/constants'
import { computeCreate1Address } from '../utils/misc'
import { BigNumber } from 'ethers'
import { getDeployedContract } from '../utils/contract'
import { AssetPool, CouponManager, CouponOracle } from '../typechain'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  if ((await deployments.getOrNull('LoanPositionManager')) !== null) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const assetPool = await getDeployedContract<AssetPool>('AssetPool')
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')

  const chainId: number = network.config.chainId || hardhat.id

  let baseURI: string
  let minDebtValueInEth: BigNumber
  if (chainId === arbitrum.id) {
    baseURI = 'LOAN_BASE_URI'
    minDebtValueInEth = BigNumber.from('1000000000000000') // TODO: change this
  } else {
    throw new Error('Unsupported network')
  }

  await deploy('LoanPositionManager', {
    from: deployer,
    args: [couponManager.address, assetPool.address, oracle.address, TREASURY[chainId], minDebtValueInEth, baseURI],
    log: true,
  })
}

deployFunction.tags = ['4']
deployFunction.dependencies = ['3']
export default deployFunction
