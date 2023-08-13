import { BigNumber, Contract, ContractTransaction } from 'ethers'

import { getHRE } from './misc'

export const waitForTx = async (tx: Promise<ContractTransaction>, confirmation?: number) => {
  return (await tx).wait(confirmation)
}

export const getDeployedContract = async <T extends Contract>(contractName: string): Promise<T> => {
  const hre = getHRE()
  const deployments = await hre.deployments.get(contractName)
  const contract = await hre.ethers.getContractAt(deployments.abi, deployments.address)
  return contract as T
}

export const buildWrapped1155Metadata = async (tokenAddress: string, epoch: number): Promise<string> => {
  const hre = getHRE()
  const token = await hre.ethers.getContractAt('IERC20Metadata', tokenAddress)
  const tokenSymbol = await token.symbol()
  const epochString = epoch.toString()
  const addLength = tokenSymbol.length + epochString.length
  const nameData = hre.ethers.utils.solidityPack(
    ['string', 'string', 'string', 'string'],
    [tokenSymbol, ' Bond Coupon (', epochString, ')'],
  )
  const symbolData = hre.ethers.utils.solidityPack(['string', 'string', 'string'], [tokenSymbol, '-CP', epochString])
  const decimal = await token.decimals()
  return hre.ethers.utils.solidityPack(
    ['bytes32', 'bytes32', 'bytes1'],
    [
      BigNumber.from(nameData)
        .add(30 + addLength)
        .toHexString(),
      BigNumber.from(symbolData)
        .add(30 + addLength)
        .toHexString(),
      decimal,
    ],
  )
}

export const convertToCouponId = (tokenAddress: string, epoch: number): BigNumber => {
  const hre = getHRE()
  return BigNumber.from(epoch)
    .shl(160)
    .add(BigNumber.from(hre.ethers.utils.getAddress(tokenAddress)))
}
