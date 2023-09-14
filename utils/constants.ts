import { arbitrum, arbitrumGoerli } from '@wagmi/chains'
import { BigNumber } from 'ethers'

export const TESTNET_ID = 7777

export const SINGLETON_FACTORY = '0xce0042B868300000d44A59004Da54A005ffdcf9f'

export const CLOBER_FACTORY: { [chainId: number]: string } = {
  [arbitrum.id]: '0x24aC0938C010Fb520F1068e96d78E0458855111D',
  [arbitrumGoerli.id]: '0x110f5cBC51576fDa2E8024155F772c494f421E11',
  [TESTNET_ID]: '0x24aC0938C010Fb520F1068e96d78E0458855111D',
}

export const AAVE_V3_POOL: { [chainId: number]: string } = {
  [arbitrum.id]: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
  [arbitrumGoerli.id]: '0x20fa38a4f8Af2E36f1Cc14caad2E603fbA5C535c',
  [TESTNET_ID]: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
}

export const WRAPPED1155_FACTORY: { [chainId: number]: string } = {
  [arbitrum.id]: '0xfcBE16BfD991E4949244E59d9b524e6964b8BB75',
  [arbitrumGoerli.id]: '0x194B27c5bb294319DE2B2DA40c10bd13484D7349',
  [TESTNET_ID]: '0xfcBE16BfD991E4949244E59d9b524e6964b8BB75',
}

export const TREASURY: { [chainId: number]: string } = {
  [arbitrum.id]: '0x000000000000000000000000000000000000dEaD', // TODO: change this
  [arbitrumGoerli.id]: '0x000000000000000000000000000000000000dEaD',
  [TESTNET_ID]: '0x000000000000000000000000000000000000dEaD',
}

export const REPAY_ROUTER: { [chainId: number]: string } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
  [arbitrumGoerli.id]: '0xbe83C53499C676dAB038db0E2CAd3E69a3d5CdFC',
  [TESTNET_ID]: '0x4b9AE05FbfEF6610c5D65B57e92c169b1A9d2Cfe',
}

export const CHAINLINK_SEQUENCER_ORACLE: { [chainId: number]: string } = {
  [arbitrum.id]: '0xFdB631F5EE196F0ed6FAa767959853A9F217697D',
  [TESTNET_ID]: '0xFdB631F5EE196F0ed6FAa767959853A9F217697D',
}

export const ORACLE_TIMEOUT: { [chainId: number]: number } = {
  [arbitrum.id]: 3600,
  [TESTNET_ID]: 3600,
}

export const SEQUENCER_GRACE_PERIOD: { [chainId: number]: number } = {
  [arbitrum.id]: 3600,
  [TESTNET_ID]: 3600,
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
  [arbitrumGoerli.id]: {
    [TOKEN_KEYS.WETH]: '0x4284186b053ACdBA28E8B26E99475d891533086a',
    [TOKEN_KEYS.USDC]: '0xd513E4537510C75E24f941f159B7CAFA74E7B3B9',
    [TOKEN_KEYS.DAI]: '0xe73C6dA65337ef99dBBc014C7858973Eba40a10b',
    [TOKEN_KEYS.USDT]: '0x8dA9412AbB78db20d0B496573D9066C474eA21B8',
    [TOKEN_KEYS.WBTC]: '0x1377b75237a9ee83aC0C76dE258E68e875d96334',
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
  [arbitrumGoerli.id]: {
    [TOKEN_KEYS.WETH]: '0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08',
    [TOKEN_KEYS.USDC]: '0x1692Bdd32F31b831caAc1b0c9fAF68613682813b',
    [TOKEN_KEYS.DAI]: '0x103b53E977DA6E4Fa92f76369c8b7e20E7fb7fe1',
    [TOKEN_KEYS.USDT]: '0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E',
    [TOKEN_KEYS.WBTC]: '0x6550bc2301936011c1334555e62A87705A81C12C',
  },
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: '0x591d4A99d7A53947Cd65C12dDba1bad8b4FEd00a',
    [TOKEN_KEYS.USDC]: '0xB2f56d91cf64466AE67E31051c0EA50b9Af923E8',
    [TOKEN_KEYS.DAI]: '0x76810BfCaea5F7f925ca9066853a70eE2a909DE1',
    [TOKEN_KEYS.USDT]: '0x436C64e8D9D39453E860E12A9FD089a2312Ef744',
    [TOKEN_KEYS.WBTC]: '0x9869A3AF7232eF832Eaa15285B2B7fD6E4A4295C',
  },
}

export const AAVE_SUBSTITUTES: { [chainId: number]: { [name: string]: string } } = {
  [arbitrumGoerli.id]: {
    [TOKEN_KEYS.WETH]: '0x37FD1b14Ba333889bC6683D7ADec9c1aE11F3227',
    [TOKEN_KEYS.USDC]: '0x6E11A012910819E0855a2505B48A5C1562BE9981',
    [TOKEN_KEYS.DAI]: '0xE426dE788f08DA8BB002D0565dD3072eC028e07D',
    [TOKEN_KEYS.USDT]: '0xaa1C9E35D766D2093899ce0DE82dA3268EFB02a3',
    [TOKEN_KEYS.WBTC]: '0xcc7eEb01352C410dC27acd3A4249E26338a6146C',
  },
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: '0x3115f897469c8f395eB80DD921099b59046ae51E',
    [TOKEN_KEYS.USDC]: '0x818d432C31E4c6cEfEfd37846Be2469065D177E7',
    [TOKEN_KEYS.DAI]: '0xeD720edc99b7E05101A9bC093fbC7A3F76A4212D',
    [TOKEN_KEYS.USDT]: '0x989cE7b1A95B48024AfAc7941446404a73194398',
    [TOKEN_KEYS.WBTC]: '0xe494b0813d70E6b9501DdFcEB2225d12B839422B',
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
