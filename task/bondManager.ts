import { task } from 'hardhat/config'
import { hardhat } from '@wagmi/chains'
import { ASSETS, getDeployedContract, waitForTx } from '../utils'
import { BondPositionManager } from '../typechain'

task('bond:register-asset')
  .addParam('asset', 'the name of the asset')
  .setAction(async ({ asset }, hre) => {
    const manager = await getDeployedContract<BondPositionManager>('BondPositionManager')
    const chainId = hre.network.config.chainId ?? hardhat.id
    const token = ASSETS[chainId][asset]
    if (await manager.isAssetRegistered(token)) {
      console.log('Asset already registered')
    } else {
      console.log('Registering asset', asset)
      const receipt = await waitForTx(manager.registerAsset(token))
      console.log('Registered asset at tx', receipt.transactionHash)
    }
  })
