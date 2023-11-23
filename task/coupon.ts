import { task } from 'hardhat/config'
import { getDeployedAddress, liveLog } from '../utils'

task('coupon:current-epoch').setAction(async (taskArgs, hre) => {
  const couponManager = await hre.viem.getContractAt('CouponManager', await getDeployedAddress('CouponManager'))
  liveLog(await couponManager.read.currentEpoch())
})
