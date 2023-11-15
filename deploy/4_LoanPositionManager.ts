import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { TREASURY } from '../utils/constants'
import { BigNumber } from 'ethers'
import { getDeployedContract } from '../utils/contract'
import { AssetPool, CouponManager, CouponOracle } from '../typechain'
import {deployWithVerify} from "../utils/misc";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('LoanPositionManager')) {
    return
  }

  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  const assetPool = await getDeployedContract<AssetPool>('AssetPool')
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')

  const chainId = network.config.chainId || hardhat.id

  const baseURI = `https://coupon.finance/api/nft/chains/${chainId}/loans/`
  const contractURI = `https://coupon.finance/api/nft/chains/${chainId}/loans`
  const minDebtValueInEth = BigNumber.from('10000000000000000')

  const args = [
    couponManager.address,
    assetPool.address,
    oracle.address,
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
