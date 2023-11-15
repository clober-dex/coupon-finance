import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { computeCreate1Address, deployWithVerify } from '../utils/misc'
import { BigNumber } from 'ethers'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments } = hre

  const [deployer] = await hre.ethers.getSigners()

  if (await deployments.getOrNull('AssetPool')) {
    return
  }

  const oracleDeployment = await deployments.get('CouponOracle')
  const firstDeployTransaction = await hre.ethers.provider.getTransaction(oracleDeployment.transactionHash ?? '')
  const nonce = await deployer.getTransactionCount('latest')
  if (nonce !== firstDeployTransaction.nonce + 1) {
    throw new Error('nonce not matched')
  }

  const computedBondPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 2))
  const computedLoanPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 3))

  const args = [[computedBondPositionManager, computedLoanPositionManager]]
  await deployWithVerify(hre, 'AssetPool', args)
}

deployFunction.tags = ['1']
deployFunction.dependencies = ['0']
export default deployFunction
