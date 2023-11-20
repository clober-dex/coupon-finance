import { arbitrum, arbitrumGoerli } from '@wagmi/chains'
import { constants } from 'ethers'

export const TESTNET_ID = 7777

export const SINGLETON_FACTORY = '0xce0042B868300000d44A59004Da54A005ffdcf9f'

export const OWNER: { [chainId: number]: string } = {
  [arbitrum.id]: '0x1689FD73FfC888d47D201b72B0ae7A83c20fA274',
  [arbitrumGoerli.id]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
  [TESTNET_ID]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
}

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
  [arbitrum.id]: '0x2f1707aed1fb24d07b9b42e4b0bc885f546b4f43',
  [arbitrumGoerli.id]: '0x000000000000000000000000000000000000dEaD',
  [TESTNET_ID]: '0x000000000000000000000000000000000000dEaD',
}

export const REPAY_ROUTER: { [chainId: number]: string } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
  [arbitrumGoerli.id]: '0xbe83C53499C676dAB038db0E2CAd3E69a3d5CdFC',
  [TESTNET_ID]: '0xBe4343BBb42347036321d8b1608311E7ed5Ea014',
}

export const LEVERAGE_ROUTER: { [chainId: number]: string } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
  [arbitrumGoerli.id]: '0xbe83C53499C676dAB038db0E2CAd3E69a3d5CdFC',
  [TESTNET_ID]: '0xBe4343BBb42347036321d8b1608311E7ed5Ea014',
}

export const LIQUIDATOR_ROUTER: { [chainId: number]: string } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
  [arbitrumGoerli.id]: '0xbe83C53499C676dAB038db0E2CAd3E69a3d5CdFC',
  [TESTNET_ID]: '0xBe4343BBb42347036321d8b1608311E7ed5Ea014',
}

export const CHAINLINK_SEQUENCER_ORACLE: { [chainId: number]: string } = {
  [arbitrum.id]: '0xFdB631F5EE196F0ed6FAa767959853A9F217697D',
  [arbitrumGoerli.id]: '0x4da69F028a5790fCCAfe81a75C0D24f46ceCDd69',
  [TESTNET_ID]: '0xFdB631F5EE196F0ed6FAa767959853A9F217697D',
}

export const ORACLE_TIMEOUT: { [chainId: number]: number } = {
  [arbitrum.id]: 24 * 3600,
  [arbitrumGoerli.id]: 24 * 3600,
  [TESTNET_ID]: 24 * 3600,
}

export const SEQUENCER_GRACE_PERIOD: { [chainId: number]: number } = {
  [arbitrum.id]: 3600,
  [arbitrumGoerli.id]: 3600,
  [TESTNET_ID]: 3600,
}

export const TOKEN_KEYS = {
  WETH: 'WETH',
  wstETH: 'wstETH',
  USDC: 'USDC',
  USDCe: 'USDC.e',
  DAI: 'DAI',
  USDT: 'USDT',
  WBTC: 'WBTC',
}

export const TOKENS: { [chainId: number]: { [name: string]: string } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    [TOKEN_KEYS.wstETH]: '0x5979D7b546E38E414F7E9822514be443A4800529',
    [TOKEN_KEYS.USDC]: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    [TOKEN_KEYS.USDCe]: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
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
    [TOKEN_KEYS.wstETH]: '0x5979D7b546E38E414F7E9822514be443A4800529',
    [TOKEN_KEYS.USDC]: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    [TOKEN_KEYS.DAI]: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    [TOKEN_KEYS.USDT]: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    [TOKEN_KEYS.WBTC]: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
  },
}

export const CHAINLINK_FEEDS: { [chainId: number]: { [name: string]: string[] } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: ['0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612'],
    [TOKEN_KEYS.wstETH]: ['0xb523ae262d20a936bc152e6023996e46fdc2a95d', '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612'],
    [TOKEN_KEYS.USDC]: ['0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3'],
    [TOKEN_KEYS.USDCe]: ['0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3'],
    [TOKEN_KEYS.DAI]: ['0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB'],
    [TOKEN_KEYS.USDT]: ['0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7'],
    [TOKEN_KEYS.WBTC]: ['0x6ce185860a4963106506C203335A2910413708e9'],
  },
  [arbitrumGoerli.id]: {
    [TOKEN_KEYS.WETH]: ['0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08'],
    [TOKEN_KEYS.USDC]: ['0x1692Bdd32F31b831caAc1b0c9fAF68613682813b'],
    [TOKEN_KEYS.DAI]: ['0x103b53E977DA6E4Fa92f76369c8b7e20E7fb7fe1'],
    [TOKEN_KEYS.USDT]: ['0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E'],
    [TOKEN_KEYS.WBTC]: ['0x6550bc2301936011c1334555e62A87705A81C12C'],
  },
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: ['0x4C0847a1A46fe953bf0673c11A083b0B449Ab7F9'],
    [TOKEN_KEYS.USDC]: ['0x9af9111087F09E9553720Ad7B4510a765f7d1a2c'],
    [TOKEN_KEYS.DAI]: ['0xd8A251F8097C5FCDe1243389737A692518D31EFb'],
    [TOKEN_KEYS.USDT]: ['0xA8633920872A0ED7DC4271ba5C7a8bb4e05F1345'],
    [TOKEN_KEYS.WBTC]: ['0x881cd5304afDfc240Bd0fDE038edcDC3e948A14b'],
  },
}

export const AAVE_SUBSTITUTES: { [chainId: number]: { [name: string]: string } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0xAb6c37355D6C06fcF73Ab0E049d9Cf922f297573',
    [TOKEN_KEYS.USDC]: '0x7Ed1145045c8B754506d375Cdf90734550d1077e',
    [TOKEN_KEYS.wstETH]: '0x4e0e151940ad5790ac087DA335F1104A5C4f6f71',
    [TOKEN_KEYS.DAI]: '0x43FE2BE829a00ba065FAF5B1170c3b0f1328eb37',
    [TOKEN_KEYS.USDCe]: '0x322d24b60795e3D4f0DD85F54FAbcd63A85dFF82',
    [TOKEN_KEYS.USDT]: '0x26185cC53695240f9298e1e81Fd95612aA19D68b',
    [TOKEN_KEYS.WBTC]: '0xCf94152a31BBC050603Ae3186b394269E4f0A8Fe',
  },
  [arbitrumGoerli.id]: {
    [TOKEN_KEYS.WETH]: '0x360ea512Be0A087Ff4A5799314e805C5d5cbA240',
    [TOKEN_KEYS.USDC]: '0xF28AA397f1dDb0b12A0e9976C808F323bFaBaB44',
    [TOKEN_KEYS.DAI]: '0xFD87c2eD28003d077217dfbb50ef3F1580a26149',
    [TOKEN_KEYS.USDT]: '0xD90FD434706b89Cb0b66b5e937f7cA09b0b13833',
    [TOKEN_KEYS.WBTC]: '0x6C460aEEa483e94E54E0e5203A9054efF066FA72',
  },
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: '0x08611448474B40D03EA5A8C5e9A56B48bf82Ea35',
    [TOKEN_KEYS.USDC]: '0xd95E71c5B175a6E7fcc2c3b5810F2d2d24124Df5',
    [TOKEN_KEYS.DAI]: '0x4e847B82C20a1d00D38f42dBc7fbB9dABce52315',
    [TOKEN_KEYS.USDT]: '0x23E558B10F8073E77E39fEaA016180f42Edfedbc',
    [TOKEN_KEYS.WBTC]: '0xecfD6e214cc41113B1cC2c9A5Dd486c4eD3c00b7',
  },
}

export type LoanConfiguration = {
  liquidationThreshold: number
  liquidationFee: number
  liquidationProtocolFee: number
  liquidationTargetLtv: number
  hook: string
}

const STABLE_STABLE_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 970000,
  liquidationFee: 10000,
  liquidationProtocolFee: 3000,
  liquidationTargetLtv: 950000,
  hook: constants.AddressZero,
}

const STABLE_VOLATILE_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 850000,
  liquidationFee: 30000,
  liquidationProtocolFee: 10000,
  liquidationTargetLtv: 750000,
  hook: constants.AddressZero,
}

const VOLATILE_VOLATILE_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 800000,
  liquidationFee: 30000,
  liquidationProtocolFee: 10000,
  liquidationTargetLtv: 700000,
  hook: constants.AddressZero,
}

const LOAN_CONFIGURATION: { [collateral: string]: { [debt: string]: LoanConfiguration } } = {
  [TOKEN_KEYS.wstETH]: {
    [TOKEN_KEYS.USDC]: STABLE_VOLATILE_LOAN_CONFIGURATION,
    [TOKEN_KEYS.WETH]: {
      liquidationThreshold: 900000,
      liquidationFee: 15000,
      liquidationProtocolFee: 5000,
      liquidationTargetLtv: 850000,
      hook: constants.AddressZero,
    },
  },
  [TOKEN_KEYS.WETH]: {
    [TOKEN_KEYS.USDC]: STABLE_VOLATILE_LOAN_CONFIGURATION,
  },
  [TOKEN_KEYS.WBTC]: {
    [TOKEN_KEYS.USDC]: STABLE_VOLATILE_LOAN_CONFIGURATION,
    [TOKEN_KEYS.WETH]: VOLATILE_VOLATILE_LOAN_CONFIGURATION,
  },
  [TOKEN_KEYS.USDCe]: {
    [TOKEN_KEYS.USDC]: STABLE_STABLE_LOAN_CONFIGURATION,
    [TOKEN_KEYS.WETH]: STABLE_VOLATILE_LOAN_CONFIGURATION,
  },
  [TOKEN_KEYS.USDC]: {
    [TOKEN_KEYS.WETH]: STABLE_VOLATILE_LOAN_CONFIGURATION,
  },
  [TOKEN_KEYS.USDT]: {
    [TOKEN_KEYS.USDC]: STABLE_STABLE_LOAN_CONFIGURATION,
    [TOKEN_KEYS.WETH]: STABLE_VOLATILE_LOAN_CONFIGURATION,
  },
  [TOKEN_KEYS.DAI]: {
    [TOKEN_KEYS.USDC]: STABLE_STABLE_LOAN_CONFIGURATION,
    [TOKEN_KEYS.WETH]: STABLE_VOLATILE_LOAN_CONFIGURATION,
  },
}

export const getLoanConfiguration = (collateral: string, debt: string): LoanConfiguration => {
  if (!Object.values(TOKEN_KEYS).includes(collateral) && !Object.values(TOKEN_KEYS).includes(debt)) {
    throw new Error('Invalid collateral or debt')
  }
  const result = LOAN_CONFIGURATION[collateral][debt]
  if (!result) {
    throw new Error('Invalid pair')
  }
  return result
}
