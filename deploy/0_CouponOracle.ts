import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { CHAINLINK_SEQUENCER_ORACLE, SEQUENCER_GRACE_PERIOD } from '../utils/constants'
import { hardhat } from '@wagmi/chains'

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, network } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  if (await deployments.getOrNull('CouponOracle')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  await deploy('CouponOracle', {
    from: deployer,
    args: [CHAINLINK_SEQUENCER_ORACLE[chainId], SEQUENCER_GRACE_PERIOD[chainId]],
    log: true,
  })
}

deployFunction.tags = ['0']
export default deployFunction
