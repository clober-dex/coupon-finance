import { task } from 'hardhat/config'
import { AAVE_SUBSTITUTES } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { getDeployedContract, waitForTx } from '../utils/contract'
import { BorrowController, LoanPositionManager, OdosRepayAdapter } from '../typechain'

task('borrow-controller:set-allowances').setAction(async (taskArgs, hre) => {
  const controller = await getDeployedContract<BorrowController>('BorrowController')
  const loanManager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokenNames = Object.keys(AAVE_SUBSTITUTES[chainId])
  const tokenAddresses = Object.values(AAVE_SUBSTITUTES[chainId])
  for (let i = 0; i < tokenNames.length; i++) {
    const token = await hre.ethers.getContractAt('IERC20Metadata', tokenAddresses[i])
    if ((await token.allowance(controller.address, loanManager.address)).gt(0)) {
      console.log(`Allowance already set for ${tokenNames[i]}`)
    } else {
      const receipt = await waitForTx(controller.setCollateralAllowance(token.address))
      console.log(`Set allowance for ${tokenNames[i]} at ${receipt.transactionHash}`)
    }
  }
})

task('odos-adapter:set-allowances').setAction(async (taskArgs, hre) => {
  const adapter = await getDeployedContract<OdosRepayAdapter>('OdosRepayAdapter')
  const loanManager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokenNames = Object.keys(AAVE_SUBSTITUTES[chainId])
  const tokenAddresses = Object.values(AAVE_SUBSTITUTES[chainId])
  for (let i = 0; i < tokenNames.length; i++) {
    const token = await hre.ethers.getContractAt('IERC20Metadata', tokenAddresses[i])
    if ((await token.allowance(adapter.address, loanManager.address)).gt(0)) {
      console.log(`Allowance already set for ${tokenNames[i]}`)
    } else {
      const receipt = await waitForTx(adapter.setCollateralAllowance(token.address))
      console.log(`Set allowance for ${tokenNames[i]} at ${receipt.transactionHash}`)
    }
  }
})
