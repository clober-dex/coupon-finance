import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { computeCreate1Address, deployWithVerify } from '../utils'
import { hardhat } from 'viem/chains'
import { Address, Hex } from 'viem'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network, getNamedAccounts } = hre

  const deployer = (await getNamedAccounts())['deployer'] as Address
  const client = await hre.viem.getPublicClient()

  if (await deployments.getOrNull('CouponManager')) {
    return
  }
  const chainId = network.config.chainId || hardhat.id

  const oracleDeployment = await deployments.get('CouponOracle')
  const firstDeployTransaction = await client.getTransaction({ hash: (oracleDeployment.transactionHash ?? '') as Hex })
  const nonce = await client.getTransactionCount({ address: deployer })
  if (nonce !== firstDeployTransaction.nonce + 2) {
    throw new Error('nonce not matched')
  }

  const baseURI = `https://coupon.finance/api/multi-token/chains/${chainId}/coupons/`
  const contractURI = `https://coupon.finance/api/multi-token/chains/${chainId}/coupons`

  const computedBondPositionManager = computeCreate1Address(deployer, nonce + 1)
  const computedLoanPositionManager = computeCreate1Address(deployer, nonce + 2)

  const args = [[computedBondPositionManager, computedLoanPositionManager], baseURI, contractURI]
  await deployWithVerify(hre, 'CouponManager', args)
}

deployFunction.tags = ['2']
deployFunction.dependencies = ['1']
export default deployFunction
