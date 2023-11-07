import { task } from 'hardhat/config'
import { AAVE_SUBSTITUTES } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { getDeployedContract, waitForTx } from '../utils/contract'
import { BorrowController, IController, RepayAdapter } from '../typechain'
import { getHRE } from '../utils/misc'

const setAllowances = async (controllerName: string, managerName: string) => {
  const hre = getHRE()
  const controller = await getDeployedContract<IController>(controllerName)
  const manager = await getDeployedContract(managerName)
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokenNames = Object.keys(AAVE_SUBSTITUTES[chainId])
  const tokenAddresses = Object.values(AAVE_SUBSTITUTES[chainId])
  console.log(`Start setting allowances of ${controllerName} to ${managerName}`)
  for (let i = 0; i < tokenNames.length; i++) {
    const token = await hre.ethers.getContractAt('IERC20Metadata', tokenAddresses[i])
    if ((await token.allowance(controller.address, manager.address)).gt(0)) {
      console.log(`Allowance already set for ${tokenNames[i]}`)
    } else {
      const receipt = await waitForTx(controller.giveManagerAllowance(token.address))
      console.log(`Set allowance for ${tokenNames[i]} at ${receipt.transactionHash}`)
    }
  }
}

task('deposit-controller:set-allowances').setAction(async (taskArgs, hre) => {
  await setAllowances('DepositController', 'BondPositionManager')
})
task('borrow-controller:set-allowances').setAction(async (taskArgs, hre) => {
  await setAllowances('BorrowController', 'LoanPositionManager')
})

task('repay-adapter:set-allowances').setAction(async (taskArgs, hre) => {
  await setAllowances('RepayAdapter', 'LoanPositionManager')
})

task('leverage-adapter:set-allowances').setAction(async (taskArgs, hre) => {
  await setAllowances('LeverageAdapter', 'LoanPositionManager')
})
