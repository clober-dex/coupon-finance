import { task } from 'hardhat/config'
import { getDeployedContract } from '../utils/contract'
import { CouponManager } from '../typechain'

task('coupon:current-epoch').setAction(async () => {
  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  console.log(await couponManager.currentEpoch())
})
