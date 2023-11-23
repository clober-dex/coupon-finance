import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { computeCreate1Address, deployWithVerify } from '../utils'
import { Address, Hex } from 'viem'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre

  const deployer = (await getNamedAccounts())['deployer'] as Address
  const client = await hre.viem.getPublicClient()

  if (await deployments.getOrNull('AssetPool')) {
    return
  }

  const oracleDeployment = await deployments.get('CouponOracle')
  const firstDeployTransaction = await client.getTransaction({ hash: (oracleDeployment.transactionHash ?? '') as Hex })
  const nonce = await client.getTransactionCount({ address: deployer })
  if (nonce !== firstDeployTransaction.nonce + 1) {
    throw new Error('nonce not matched')
  }

  const computedBondPositionManager = computeCreate1Address(deployer, nonce + 2)
  const computedLoanPositionManager = computeCreate1Address(deployer, nonce + 3)

  const args = [[computedBondPositionManager, computedLoanPositionManager]]
  await deployWithVerify(hre, 'AssetPool', args)
}

deployFunction.tags = ['1']
deployFunction.dependencies = ['0']
export default deployFunction
