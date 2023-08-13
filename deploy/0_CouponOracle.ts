import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from '@wagmi/chains'
import { CHAINLINK_FEEDS } from '../utils/constants'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  if (await deployments.getOrNull('CouponOracle')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id
  const oracleAssets = [hre.ethers.constants.AddressZero]
  const oracleFeeds = [CHAINLINK_FEEDS[chainId].WETH]

  await deploy('CouponOracle', {
    from: deployer,
    args: [oracleAssets, oracleFeeds],
    log: true,
  })
}

deployFunction.tags = ['0']
export default deployFunction
