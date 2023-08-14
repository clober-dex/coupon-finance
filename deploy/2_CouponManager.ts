import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { computeCreate1Address } from '../utils/misc'
import { BigNumber } from 'ethers'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments } = hre
  const { deploy } = deployments

  const [deployer] = await hre.ethers.getSigners()

  if (await deployments.getOrNull('CouponManager')) {
    return
  }

  const oracleDeployment = await deployments.get('CouponOracle')
  const firstDeployTransaction = await hre.ethers.provider.getTransaction(oracleDeployment.transactionHash ?? '')
  const nonce = await deployer.getTransactionCount('latest')
  if (nonce !== firstDeployTransaction.nonce + 2) {
    throw new Error('nonce not matched')
  }

  const baseURI = 'COUPON_BASE_URI'

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
