import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { arbitrum, hardhat } from '@wagmi/chains'
import { CHAINLINK_FEEDS, TOKENS } from '../utils/constants'
import { computeCreate1Address } from '../utils/misc'
import { BigNumber } from 'ethers'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre
  const { deploy } = deployments

  const [deployer] = await hre.ethers.getSigners()

  if ((await deployments.getOrNull('CouponManager')) !== null) {
    return
  }

  const chainId: number = network.config.chainId || hardhat.id
  const nonce = await deployer.getTransactionCount('latest')
  if (nonce !== 2) {
    throw new Error('nonce not matched')
  }

  let baseURI
  if (chainId === arbitrum.id) {
    baseURI = 'COUPON_BASE_URI'
  } else {
    throw new Error('Unsupported network')
  }

  const computedBondPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 1))
  const computedLoanPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 2))
  await deploy('CouponManager', {
    from: deployer.address,
    args: [[computedBondPositionManager, computedLoanPositionManager], baseURI],
    log: true,
  })
}

deployFunction.tags = ['2']
deployFunction.dependencies = ['1']
export default deployFunction
