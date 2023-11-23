import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'
import { TREASURY, deployWithVerify, getDeployedAddress } from '../utils'
import { BigNumber } from 'ethers'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('LoanPositionManager')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const baseURI = `https://coupon.finance/api/nft/chains/${chainId}/loans/`
  const contractURI = `https://coupon.finance/api/nft/chains/${chainId}/loans`
  const minDebtValueInEth = BigNumber.from('10000000000000000')

  const args = [
    await getDeployedAddress('CouponManager'),
    await getDeployedAddress('AssetPool'),
    await getDeployedAddress('CouponOracle'),
    TREASURY[chainId],
    minDebtValueInEth,
    baseURI,
    contractURI,
  ]
  await deployWithVerify(hre, 'LoanPositionManager', args)
}

deployFunction.tags = ['4']
deployFunction.dependencies = ['3']
export default deployFunction
