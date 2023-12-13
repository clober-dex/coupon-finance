import { task } from 'hardhat/config'
import { hardhat } from 'viem/chains'
import { ASSETS, getDeployedAddress, liveLog } from '../utils'

task('bond:register-asset')
  .addParam('asset', 'the name of the asset')
  .setAction(async ({ asset }, hre) => {
    const manager = await hre.viem.getContractAt('BondPositionManager', await getDeployedAddress('BondPositionManager'))
    const chainId = hre.network.config.chainId ?? hardhat.id
    const token = ASSETS[chainId][asset]
    if (await manager.read.isAssetRegistered([token])) {
      liveLog('Asset already registered')
    } else {
      liveLog('Registering asset', asset)
      const transactionHash = await manager.write.registerAsset([token])
      liveLog('Registered asset at tx', transactionHash)
    }
  })
