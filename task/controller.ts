import { task } from 'hardhat/config'
import { AAVE_SUBSTITUTES } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { getDeployedContract, waitForTx } from '../utils/contract'
import { BorrowController, LoanPositionManager } from '../typechain'

task('borrow-controller:set-allowances').setAction(async (taskArgs, hre) => {
  const controller = await getDeployedContract<BorrowController>('BorrowController')
  const loanManager = await getDeployedContract<LoanPositionManager>('LoanPositionManager')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokenAddresses = Object.keys(AAVE_SUBSTITUTES[chainId])
  for (const tokenAddress of tokenAddresses) {
    const token = await hre.ethers.getContractAt('IERC20Metadata', tokenAddress)
    if ((await token.allowance(controller.address, loanManager.address)).gt(0)) {
      console.log(`Allowance already set for ${tokenAddress}`)
    } else {
      const receipt = await waitForTx(controller.setCollateralAllowance(token.address))
      console.log(`Set allowance for ${tokenAddress} at ${receipt.transactionHash}`)
    }
  }
})
