import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { arbitrum, hardhat } from '@wagmi/chains'
import { CHAINLINK_FEEDS } from '../utils/constants'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  if ((await deployments.getOrNull('CouponOracle')) !== null) {
    return
  }

  const chainId: number = network.config.chainId || hardhat.id
  let oracleAssets: string[]
  let oracleFeeds: string[]
  if (chainId === arbitrum.id) {
    oracleAssets = [hre.ethers.constants.AddressZero]
    oracleFeeds = [CHAINLINK_FEEDS[chainId].WETH]
  } else {
    throw new Error('Unsupported network')
  }

  await deploy('CouponOracle', {
    from: deployer,
    args: [oracleAssets, oracleFeeds],
    log: true,
  })
}

deployFunction.tags = ['0']
export default deployFunction
