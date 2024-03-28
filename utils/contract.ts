import { getHRE, liveLog } from './misc'
import { Address, encodePacked, Hex, keccak256, numberToHex } from 'viem'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

export const getDeployedAddress = async (contractName: string): Promise<Address> => {
  const hre = getHRE()
  return (await hre.deployments.get(contractName)).address as Address
}

export const verify = async (contractAddress: string, args: any[]) => {
  liveLog(`Verifying Contract: ${contractAddress}`)
  try {
    await getHRE().run('verify:verify', {
      address: contractAddress,
      constructorArguments: args,
    })
  } catch (e) {
    console.log(e)
  }
}

export const deployWithVerify = async (hre: HardhatRuntimeEnvironment, name: string, args?: any[]) => {
  const { deployer } = await hre.getNamedAccounts()
  const deployedAddress = (
    await hre.deployments.deploy(name, {
      from: deployer,
      args: args,
      log: true,
    })
  ).address

  await hre.run('verify:verify', {
    address: deployedAddress,
    constructorArguments: args,
  })
}

export const buildWrapped1155Metadata = async (tokenAddress: Address, epoch: number): Promise<string> => {
  const hre = getHRE()
  const token = await hre.viem.getContractAt('IERC20Metadata', tokenAddress)
  const tokenSymbol = await token.read.symbol()
  const epochString = epoch.toString()
  const addLength = (tokenSymbol.length + epochString.length) * 2
  const nameData = encodePacked(
    ['string', 'string', 'string', 'string'],
    [tokenSymbol, ' Bond Coupon (', epochString, ')'],
  ).padEnd(66, '0')
  const symbolData = encodePacked(['string', 'string', 'string'], [tokenSymbol, '-CP', epochString]).padEnd(66, '0')
  const decimal = await token.read.decimals()
  return encodePacked(
    ['bytes32', 'bytes32', 'bytes1'],
    [
      numberToHex(BigInt(nameData) + BigInt(30 + addLength), { size: 32 }),
      numberToHex(BigInt(symbolData) + BigInt(6 + addLength), { size: 32 }),
      numberToHex(BigInt(decimal), { size: 1 }),
    ],
  )
}

export const convertToCouponId = (tokenAddress: Address, epoch: number): bigint => {
  return (BigInt(epoch) << 160n) + BigInt(tokenAddress)
}

export const computeCreate1Address = (origin: `0x${string}`, nonce: bigint | number): string => {
  let packedData: Hex
  nonce = BigInt(nonce)
  if (nonce === 0n) {
    packedData = encodePacked(['bytes1', 'bytes1', 'address', 'bytes1'], ['0xd6', '0x94', origin, '0x80'])
  } else if (nonce <= BigInt('0x7f')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1'],
      ['0xd6', '0x94', origin, `0x${Number(nonce).toString(16).padStart(2, '0')}`],
    )
  } else if (nonce <= BigInt('0xff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint8'],
      ['0xd7', '0x94', origin, '0x81', Number(nonce)],
    )
  } else if (nonce <= BigInt('0xffff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint16'],
      ['0xd8', '0x94', origin, '0x82', Number(nonce)],
    )
  } else if (nonce <= BigInt('0xffffff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint24'],
      ['0xd9', '0x94', origin, '0x83', Number(nonce)],
    )
  } else if (nonce <= BigInt('0xffffffff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint32'],
      ['0xda', '0x94', origin, '0x84', Number(nonce)],
    )
  } else if (nonce <= BigInt('0xffffffffff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint40'],
      ['0xdb', '0x94', origin, '0x85', Number(nonce)],
    )
  } else if (nonce <= BigInt('0xffffffffffff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint48'],
      ['0xdc', '0x94', origin, '0x86', Number(nonce)],
    )
  } else if (nonce <= BigInt('0xffffffffffffff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint56'],
      ['0xdd', '0x94', origin, '0x87', nonce],
    )
  } else if (nonce < BigInt('0xffffffffffffffff')) {
    packedData = encodePacked(
      ['bytes1', 'bytes1', 'address', 'bytes1', 'uint64'],
      ['0xde', '0x94', origin, '0x88', nonce],
    )
  } else {
    // Cannot deploy contract when the nonce is type(uint64).max
    throw new Error('MAX_NONCE')
  }
  return '0x' + keccak256(packedData).slice(-40)
}
