import { task } from 'hardhat/config'
import { AAVE_SUBSTITUTES, getLoanConfiguration } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { getDeployedContract, waitForTx } from '../utils/contract'
import { LoanPositionManager } from '../typechain'

task('loan:set-configuration')
  .addParam('collateral', 'the name of the collateral asset')
  .addParam('debt', 'the name of the debt asset')
  .setAction(async ({ collateral, debt }, hre) => {
    const manager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')
    const chainId = hre.network.config.chainId ?? hardhat.id
    const collateralToken = AAVE_SUBSTITUTES[chainId][collateral]
    const debtToken = AAVE_SUBSTITUTES[chainId][debt]
    const configuration = getLoanConfiguration(collateral, debt)
    if (await manager.isPairRegistered(collateralToken, debtToken)) {
      console.log('Pair already registered')
    } else {
      const receipt = await waitForTx(
        manager.setLoanConfiguration(
          collateralToken,
          debtToken,
          configuration.liquidationThreshold,
          configuration.liquidationFee,
          configuration.liquidationProtocolFee,
          configuration.liquidationTargetLtv,
          configuration.hook,
        ),
      )
      console.log('Registered pair at tx', receipt.transactionHash)
    }
  })

task('loan:get-configuration')
  .addParam('collateral', 'the name of the collateral asset')
  .addParam('debt', 'the name of the debt asset')
  .setAction(async ({ collateral, debt }, hre) => {
    const manager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')
    const chainId = hre.network.config.chainId ?? hardhat.id
    const collateralToken = AAVE_SUBSTITUTES[chainId][collateral]
    const debtToken = AAVE_SUBSTITUTES[chainId][debt]
    const configuration = await manager.getLoanConfiguration(collateralToken, debtToken)
    console.log('liquidationThreshold', configuration.liquidationThreshold / 10 ** 6)
    console.log('liquidationFee', configuration.liquidationFee / 10 ** 6)
    console.log('liquidationProtocolFee', configuration.liquidationProtocolFee / 10 ** 6)
    console.log('liquidationTargetLtv', configuration.liquidationTargetLtv / 10 ** 6)
  })
