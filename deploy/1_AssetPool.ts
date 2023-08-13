import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { arbitrum, hardhat } from '@wagmi/chains'
import { CHAINLINK_FEEDS, TOKENS } from '../utils/constants'
import { computeCreate1Address } from '../utils/misc'
import { BigNumber } from 'ethers'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments } = hre
  const { deploy } = deployments

  const [deployer] = await hre.ethers.getSigners()

  if ((await deployments.getOrNull('AssetPool')) !== null) {
    return
  }

  const couponOracleDeployment = await deployments.get('CouponOracle')
  const firstDeployTransaction = await hre.ethers.provider.getTransaction(couponOracleDeployment.transactionHash ?? '')
  const nonce = await deployer.getTransactionCount('latest')
  if (nonce !== firstDeployTransaction.nonce + 1) {
    throw new Error('nonce not matched')
  }

  const computedBondPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 2))
  const computedLoanPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 3))
  await deploy('AssetPool', {
    from: deployer.address,
    args: [[computedBondPositionManager, computedLoanPositionManager]],
    log: true,
  })
}

deployFunction.tags = ['1']
deployFunction.dependencies = ['0']
export default deployFunction
