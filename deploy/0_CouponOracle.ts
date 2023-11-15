import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { CHAINLINK_SEQUENCER_ORACLE, ORACLE_TIMEOUT, SEQUENCER_GRACE_PERIOD } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import {CouponOracle} from "../typechain";
import {deployWithVerify} from "../utils/misc";

const deployFunction: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, network } = hre

  if (await deployments.getOrNull('CouponOracle')) {
    return
  }

  const chainId = network.config.chainId || hardhat.id

  const args = [CHAINLINK_SEQUENCER_ORACLE[chainId], ORACLE_TIMEOUT[chainId], SEQUENCER_GRACE_PERIOD[chainId]]
  await deployWithVerify(hre, 'CouponOracle', args)
}

deployFunction.tags = ['0']
export default deployFunction
