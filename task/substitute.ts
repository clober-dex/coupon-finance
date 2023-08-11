import { task } from 'hardhat/config'
import { AAVE_V3_POOL, SINGLETON_FACTORY, TREASURY } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { waitForTx } from '../utils/contract'

task('substitute:aave:deploy')
  .addParam<string>('asset', 'address of the asset')
  .setAction(async ({ asset }, hre) => {
    const [signer] = await hre.ethers.getSigners()
    const singletonFactory = await hre.ethers.getContractAt('ISingletonFactory', SINGLETON_FACTORY)
    const aaveTokenSubstituteFactory = await hre.ethers.getContractFactory('AaveTokenSubstitute')
    const aaveV3Pool = AAVE_V3_POOL[hre.network.config.chainId ?? hardhat.id]
    const treasury = TREASURY[hre.network.config.chainId ?? hardhat.id]
    if (!aaveV3Pool || !treasury) {
      throw new Error('missing aaveV3Pool or treasury')
    }
    const constructorArguments = aaveTokenSubstituteFactory.interface.encodeDeploy([
      asset,
      aaveV3Pool,
      treasury,
      signer.address,
    ])
    const initCode = hre.ethers.utils.solidityPack(
      ['bytes', 'bytes'],
      [aaveTokenSubstituteFactory.bytecode, constructorArguments],
    )
    const computedAddress = hre.ethers.utils.getCreate2Address(
      singletonFactory.address,
      hre.ethers.constants.HashZero,
      hre.ethers.utils.keccak256(initCode),
    )
    if ((await hre.ethers.provider.getCode(computedAddress)) !== '0x') {
      console.log('Contract already deployed')
      return
    }
    const receipt = await waitForTx(singletonFactory.deploy(initCode, hre.ethers.constants.HashZero))
    console.log('Deployed AaveTokenSubstitute at tx', receipt.transactionHash)
  })

task('substitute:set-treasury')
  .addParam('address', 'address of the substitute')
  .setAction(async ({ address }, hre) => {
    const treasury = TREASURY[hre.network.config.chainId ?? hardhat.id]
    if (!treasury) {
      throw new Error('missing treasury')
    }
    const substitute = await hre.ethers.getContractAt('ISubstitute', address)
    const receipt = await waitForTx(substitute.setTreasury(treasury))
    console.log('Set treasury at tx', receipt.transactionHash)
  })

task('substitute:claim')
  .addParam('address', 'address of the substitute')
  .setAction(async ({ address }, hre) => {
    const substitute = await hre.ethers.getContractAt('ISubstitute', address)
    const receipt = await waitForTx(substitute.claim())
    console.log('Claimed at tx', receipt.transactionHash)
  })
