import { task } from 'hardhat/config'
import { AAVE_SUBSTITUTES, CLOBER_FACTORY, TREASURY, WRAPPED1155_FACTORY } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { buildWrapped1155Metadata, convertToCouponId, getDeployedContract, waitForTx } from '../utils/contract'
import { BorrowController, CouponManager, DepositController } from '../typechain'
import { BigNumber } from 'ethers'

task('coupon:current-epoch').setAction(async () => {
  const couponManager = await getDeployedContract<CouponManager>('CouponManager')
  console.log(await couponManager.currentEpoch())
})

task('coupon:deploy-wrapped-token')
  .addParam('asset', 'the name of the asset')
  .addParam('epoch', 'the epoch number')
  .setAction(async ({ asset, epoch }, hre) => {
    const couponManager = await getDeployedContract<CouponManager>('CouponManager')
    const chainId = hre.network.config.chainId ?? hardhat.id
    const wrapped1155Factory = await hre.ethers.getContractAt('IWrapped1155Factory', WRAPPED1155_FACTORY[chainId])
    const token = AAVE_SUBSTITUTES[chainId][asset]
    if (epoch < (await couponManager.currentEpoch())) {
      throw new Error('Cannot deploy for past epoch')
    }
    const metadata = buildWrapped1155Metadata(token, epoch)
    const couponId = convertToCouponId(token, epoch)
    const computedAddress = await wrapped1155Factory.getWrapped1155(couponManager.address, couponId, metadata)
    if ((await hre.ethers.provider.getCode(computedAddress)) !== '0x') {
      console.log('Already deployed:', computedAddress)
      return
    }
    const receipt = await waitForTx(wrapped1155Factory.requireWrapped1155(couponManager.address, couponId, metadata))
    console.log(`Deployed ${token} for epoch ${epoch} at ${computedAddress} at ${receipt.transactionHash}`)
  })

task('coupon:create-clober-market')
  .addParam('asset', 'the name of the asset')
  .addParam('epoch', 'the epoch number')
  .setAction(async ({ asset, epoch }, hre) => {
    const couponManager = await getDeployedContract<CouponManager>('CouponManager')
    const chainId = hre.network.config.chainId ?? hardhat.id
    const wrapped1155Factory = await hre.ethers.getContractAt('IWrapped1155Factory', WRAPPED1155_FACTORY[chainId])
    const cloberFactory = await hre.ethers.getContractAt('CloberMarketFactory', CLOBER_FACTORY[chainId])
    const depositController = await getDeployedContract<DepositController>('DepositController')
    const borrowController = await getDeployedContract<BorrowController>('BorrowController')
    const token = AAVE_SUBSTITUTES[chainId][asset]
    if (epoch < (await couponManager.currentEpoch())) {
      throw new Error('Cannot deploy for past epoch')
    }
    const computedAddress = await wrapped1155Factory.getWrapped1155(
      couponManager.address,
      convertToCouponId(token, epoch),
      buildWrapped1155Metadata(token, epoch),
    )
    const decimals = await (await hre.ethers.getContractAt('IERC20Metadata', token)).decimals()
    let receipt = await waitForTx(
      cloberFactory.createVolatileMarket(
        TREASURY[chainId],
        token,
        computedAddress,
        decimals < 9 ? 1 : BigNumber.from(10).pow(9),
        0,
        400,
        BigNumber.from(10).pow(10),
        BigNumber.from(10).pow(15).mul(1001),
      ),
    )
    const event = receipt.events?.filter((e) => e.event == 'CreateVolatileMarket')[0]
    // @ts-ignore
    const deployedAddress = event.args[0]
    console.log(`Created market for ${asset}-${epoch} at ${deployedAddress} on tx ${receipt.transactionHash}`)

    receipt = await waitForTx(depositController.setCouponMarket({ asset: token, epoch }, deployedAddress))
    console.log(`Set deposit controller for ${asset}-${epoch} to ${deployedAddress} on tx ${receipt.transactionHash}`)

    receipt = await waitForTx(borrowController.setCouponMarket({ asset: token, epoch }, deployedAddress))
    console.log(`Set borrow controller for ${asset}-${epoch} to ${deployedAddress} on tx ${receipt.transactionHash}`)
  })
