import { task } from 'hardhat/config'
import { hardhat } from 'viem/chains'
import { ASSETS, getLoanConfiguration, getDeployedAddress, liveLog } from '../utils'

task('loan:set-configuration')
  .addParam('collateral', 'the name of the collateral asset')
  .addParam('debt', 'the name of the debt asset')
  .setAction(async ({ collateral, debt }, hre) => {
    const manager = await hre.viem.getContractAt('LoanPositionManager', await getDeployedAddress('LoanPositionManager'))
    const chainId = hre.network.config.chainId ?? hardhat.id
    const collateralToken = ASSETS[chainId][collateral]
    const debtToken = ASSETS[chainId][debt]
    const configuration = getLoanConfiguration(collateral, debt)
    if (await manager.read.isPairRegistered([collateralToken, debtToken])) {
      liveLog('Pair already registered')
    } else {
      const transactionHash = await manager.write.setLoanConfiguration([
        collateralToken,
        debtToken,
        configuration.liquidationThreshold,
        configuration.liquidationFee,
        configuration.liquidationProtocolFee,
        configuration.liquidationTargetLtv,
        configuration.hook,
      ])
      liveLog(`Registered pair(${collateral}-${debt}) at tx`, transactionHash)
    }
  })

task('loan:get-configuration')
  .addParam('collateral', 'the name of the collateral asset')
  .addParam('debt', 'the name of the debt asset')
  .setAction(async ({ collateral, debt }, hre) => {
    const manager = await hre.viem.getContractAt('LoanPositionManager', await getDeployedAddress('LoanPositionManager'))
    const chainId = hre.network.config.chainId ?? hardhat.id
    const collateralToken = ASSETS[chainId][collateral]
    const debtToken = ASSETS[chainId][debt]
    const configuration = await manager.read.getLoanConfiguration([collateralToken, debtToken])
    liveLog(`${collateral}-${debt}`)
    liveLog('liquidationThreshold', configuration.liquidationThreshold / 10 ** 6)
    liveLog('liquidationFee', configuration.liquidationFee / 10 ** 6)
    liveLog('liquidationProtocolFee', configuration.liquidationProtocolFee / 10 ** 6)
    liveLog('liquidationTargetLtv', configuration.liquidationTargetLtv / 10 ** 6)
  })
