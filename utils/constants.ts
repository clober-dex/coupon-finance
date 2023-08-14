import { arbitrum } from '@wagmi/chains'
import { BigNumber } from 'ethers'

export const TESTNET_ID = 7777

export const SINGLETON_FACTORY = '0xce0042B868300000d44A59004Da54A005ffdcf9f'

export const CLOBER_FACTORY: { [chainId: number]: string } = {
  [arbitrum.id]: '0x24aC0938C010Fb520F1068e96d78E0458855111D',
  [TESTNET_ID]: '0x24aC0938C010Fb520F1068e96d78E0458855111D',
}

export const AAVE_V3_POOL: { [chainId: number]: string } = {
  [arbitrum.id]: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
  [TESTNET_ID]: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
}

export const WRAPPED1155_FACTORY: { [chainId: number]: string } = {
  [arbitrum.id]: '0xfcBE16BfD991E4949244E59d9b524e6964b8BB75',
  [TESTNET_ID]: '0xfcBE16BfD991E4949244E59d9b524e6964b8BB75',
}

export const TREASURY: { [chainId: number]: string } = {
  [arbitrum.id]: '0x000000000000000000000000000000000000dEaD', // TODO: change this
  [TESTNET_ID]: '0x000000000000000000000000000000000000dEaD',
}

const TOKEN_KEYS = {
  WETH: 'WETH',
  USDC: 'USDC',
  DAI: 'DAI',
  USDT: 'USDT',
  WBTC: 'WBTC',
}

const STABLES = [TOKEN_KEYS.USDC, TOKEN_KEYS.DAI, TOKEN_KEYS.USDT]

export const TOKENS: { [chainId: number]: { [name: string]: string } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    [TOKEN_KEYS.USDC]: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    [TOKEN_KEYS.DAI]: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    [TOKEN_KEYS.USDT]: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    [TOKEN_KEYS.WBTC]: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
  },
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    [TOKEN_KEYS.USDC]: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    [TOKEN_KEYS.DAI]: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    [TOKEN_KEYS.USDT]: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    [TOKEN_KEYS.WBTC]: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
  },
}

export const CHAINLINK_FEEDS: { [chainId: number]: { [name: string]: string } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
    [TOKEN_KEYS.USDC]: '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3',
    [TOKEN_KEYS.DAI]: '0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB',
    [TOKEN_KEYS.USDT]: '0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7',
    [TOKEN_KEYS.WBTC]: '0x6ce185860a4963106506C203335A2910413708e9',
  },
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: '0x01B8fC27B0fe6c820d58aEe86735555186FCA503',
    [TOKEN_KEYS.USDC]: '0xA905EDf35a0c15A10CE571564E26E6Ba92e8a5E1',
    [TOKEN_KEYS.DAI]: '0xd6F615af3bcba1FD02C678D6B6a06d59FaAdaE25',
    [TOKEN_KEYS.USDT]: '0xFE20e9E42217918D910A5231f16D24150c649e8b',
    [TOKEN_KEYS.WBTC]: '0xcb87124387A71De8F892B795604C7f73F5Fde711',
  },
}

export const AAVE_SUBSTITUTES: { [chainId: number]: { [name: string]: string } } = {
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: '0x3F14418813B774e49A029b3D7B6193c31c7Daf23',
    [TOKEN_KEYS.USDC]: '0x422370Bc18Ae971817aB226c5552f0400ffE2263',
    [TOKEN_KEYS.DAI]: '0xEa14C87C1fAe9EB19614E498c86d9Df12dC95BAF',
    [TOKEN_KEYS.USDT]: '0xFB848FACc3A13Dbd673d85ae533f3f5BD447029D',
    [TOKEN_KEYS.WBTC]: '0xb48B8CAC2f3dE9cca8FCbdcc37990490AAb0BED5',
  },
}

export type LoanConfiguration = {
  liquidationThreshold: number
  liquidationFee: number
  liquidationProtocolFee: number
  liquidationTargetLtv: number
}

const DEFAULT_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 800000,
  liquidationFee: 25000,
  liquidationProtocolFee: 5000,
  liquidationTargetLtv: 700000,
}

const STABLE_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 900000,
  liquidationFee: 25000,
  liquidationProtocolFee: 5000,
  liquidationTargetLtv: 800000,
}

const LOAN_CONFIGURATION: { [collateral: string]: { [debt: string]: LoanConfiguration } } = {}

export const getLoanConfiguration = (collateral: string, debt: string): LoanConfiguration => {
  if (!Object.values(TOKEN_KEYS).includes(collateral) && !Object.values(TOKEN_KEYS).includes(debt)) {
    throw new Error('Invalid collateral or debt')
  }
  if (collateral === debt) {
    return STABLE_LOAN_CONFIGURATION
  }
  if (STABLES.includes(debt) && STABLES.includes(collateral)) {
    return STABLE_LOAN_CONFIGURATION
  }
  return LOAN_CONFIGURATION[collateral]?.[debt] ?? DEFAULT_LOAN_CONFIGURATION
}
