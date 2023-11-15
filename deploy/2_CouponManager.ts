import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import {computeCreate1Address, deployWithVerify} from '../utils/misc'
import { BigNumber } from 'ethers'
import { hardhat } from '@wagmi/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  const [deployer] = await hre.ethers.getSigners()

  if (await deployments.getOrNull('CouponManager')) {
    return
  }
  const chainId = network.config.chainId || hardhat.id

  const oracleDeployment = await deployments.get('CouponOracle')
  const firstDeployTransaction = await hre.ethers.provider.getTransaction(oracleDeployment.transactionHash ?? '')
  const nonce = await deployer.getTransactionCount('latest')
  if (nonce !== firstDeployTransaction.nonce + 2) {
    throw new Error('nonce not matched')
  }

  const baseURI = `https://coupon.finance/api/multi-token/chains/${chainId}/coupons/`
  const contractURI = `https://coupon.finance/api/multi-token/chains/${chainId}/coupons`

  const computedBondPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 1))
  const computedLoanPositionManager = computeCreate1Address(deployer.address, BigNumber.from(nonce + 2))

  const args = [[computedBondPositionManager, computedLoanPositionManager], baseURI, contractURI]
  await deployWithVerify(hre, 'CouponManager', args)
}

deployFunction.tags = ['2']
deployFunction.dependencies = ['1']
export default deployFunction
