import { arbitrum, arbitrumSepolia } from 'viem/chains'
import { Address, zeroAddress } from 'viem'

export const TESTNET_ID = 7777

export const OWNER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x1689FD73FfC888d47D201b72B0ae7A83c20fA274',
  [arbitrumSepolia.id]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
  [TESTNET_ID]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
}

export const TREASURY: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x2f1707aed1fb24d07b9b42e4b0bc885f546b4f43',
  [arbitrumSepolia.id]: '0x000000000000000000000000000000000000dEaD',
  [TESTNET_ID]: '0x000000000000000000000000000000000000dEaD',
}

export const CHAINLINK_SEQUENCER_ORACLE: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xFdB631F5EE196F0ed6FAa767959853A9F217697D',
  [arbitrumSepolia.id]: '0x8B0f27aDf87E037B53eF1AADB96bE629Be37CeA8',
  [TESTNET_ID]: '0xFdB631F5EE196F0ed6FAa767959853A9F217697D',
}

export const ORACLE_TIMEOUT: { [chainId: number]: number } = {
  [arbitrum.id]: 24 * 3600,
  [arbitrumSepolia.id]: 24 * 3600,
  [TESTNET_ID]: 24 * 3600,
}

export const SEQUENCER_GRACE_PERIOD: { [chainId: number]: number } = {
  [arbitrum.id]: 3600,
  [arbitrumSepolia.id]: 3600,
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
  ARB: 'ARB',
  GMX: 'GMX',
}

export type TokenKeys = (typeof TOKEN_KEYS)[keyof typeof TOKEN_KEYS]

export const TOKENS: { [chainId: number]: { [name: TokenKeys]: Address } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    [TOKEN_KEYS.wstETH]: '0x5979D7b546E38E414F7E9822514be443A4800529',
    [TOKEN_KEYS.USDC]: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    [TOKEN_KEYS.USDCe]: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
    [TOKEN_KEYS.DAI]: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    [TOKEN_KEYS.USDT]: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    [TOKEN_KEYS.WBTC]: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
    [TOKEN_KEYS.ARB]: '0x912CE59144191C1204E64559FE8253a0e49E6548',
    [TOKEN_KEYS.GMX]: '0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a',
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

export const CHAINLINK_FEEDS: { [chainId: number]: { [name: TokenKeys]: Address[] } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: ['0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612'],
    [TOKEN_KEYS.wstETH]: ['0xb523ae262d20a936bc152e6023996e46fdc2a95d', '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612'],
    [TOKEN_KEYS.USDC]: ['0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3'],
    [TOKEN_KEYS.USDCe]: ['0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3'],
    [TOKEN_KEYS.DAI]: ['0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB'],
    [TOKEN_KEYS.USDT]: ['0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7'],
    [TOKEN_KEYS.WBTC]: ['0x6ce185860a4963106506C203335A2910413708e9'],
    [TOKEN_KEYS.ARB]: ['0xb2a824043730fe05f3da2efafa1cbbe83fa548d6'],
    [TOKEN_KEYS.GMX]: ['0xdb98056fecfff59d032ab628337a4887110df3db'],
  },
  [arbitrumSepolia.id]: {
    [TOKEN_KEYS.WETH]: ['0x694AA1769357215DE4FAC081bf1f309aDC325306'],
    [TOKEN_KEYS.USDC]: ['0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E'],
    [TOKEN_KEYS.DAI]: ['0x14866185B1962B63C3Ea9E03Bc1da838bab34C19'],
    [TOKEN_KEYS.WBTC]: ['0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43'],
  },
  [TESTNET_ID]: {
    [TOKEN_KEYS.WETH]: ['0x4C0847a1A46fe953bf0673c11A083b0B449Ab7F9'],
    [TOKEN_KEYS.USDC]: ['0x9af9111087F09E9553720Ad7B4510a765f7d1a2c'],
    [TOKEN_KEYS.DAI]: ['0xd8A251F8097C5FCDe1243389737A692518D31EFb'],
    [TOKEN_KEYS.USDT]: ['0xA8633920872A0ED7DC4271ba5C7a8bb4e05F1345'],
    [TOKEN_KEYS.WBTC]: ['0x881cd5304afDfc240Bd0fDE038edcDC3e948A14b'],
  },
}

export const ASSETS: { [chainId: number]: { [name: TokenKeys]: Address } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0xAb6c37355D6C06fcF73Ab0E049d9Cf922f297573',
    [TOKEN_KEYS.USDC]: '0x7Ed1145045c8B754506d375Cdf90734550d1077e',
    [TOKEN_KEYS.wstETH]: '0x4e0e151940ad5790ac087DA335F1104A5C4f6f71',
    [TOKEN_KEYS.DAI]: '0x43FE2BE829a00ba065FAF5B1170c3b0f1328eb37',
    [TOKEN_KEYS.USDCe]: '0x322d24b60795e3D4f0DD85F54FAbcd63A85dFF82',
    [TOKEN_KEYS.USDT]: '0x26185cC53695240f9298e1e81Fd95612aA19D68b',
    [TOKEN_KEYS.WBTC]: '0xCf94152a31BBC050603Ae3186b394269E4f0A8Fe',
    [TOKEN_KEYS.ARB]: '0x3D3d18B22b6EB47ffC21ca226E506Bd1C5C7cc00',
  },
  [arbitrumSepolia.id]: {},
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
  hook: Address
}

const STABLE_STABLE_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 970000,
  liquidationFee: 10000,
  liquidationProtocolFee: 3000,
  liquidationTargetLtv: 950000,
  hook: zeroAddress,
}

const STABLE_VOLATILE_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 850000,
  liquidationFee: 30000,
  liquidationProtocolFee: 10000,
  liquidationTargetLtv: 750000,
  hook: zeroAddress,
}

const VOLATILE_VOLATILE_LOAN_CONFIGURATION: LoanConfiguration = {
  liquidationThreshold: 800000,
  liquidationFee: 30000,
  liquidationProtocolFee: 10000,
  liquidationTargetLtv: 700000,
  hook: zeroAddress,
}

const LOAN_CONFIGURATION: { [collateral: TokenKeys]: { [debt: TokenKeys]: LoanConfiguration } } = {
  [TOKEN_KEYS.wstETH]: {
    [TOKEN_KEYS.USDC]: STABLE_VOLATILE_LOAN_CONFIGURATION,
    [TOKEN_KEYS.WETH]: {
      liquidationThreshold: 900000,
      liquidationFee: 15000,
      liquidationProtocolFee: 5000,
      liquidationTargetLtv: 850000,
      hook: zeroAddress,
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

export const getLoanConfiguration = (collateral: TokenKeys, debt: TokenKeys): LoanConfiguration => {
  if (!Object.values(TOKEN_KEYS).includes(collateral) && !Object.values(TOKEN_KEYS).includes(debt)) {
    throw new Error('Invalid collateral or debt')
  }
  const result = LOAN_CONFIGURATION[collateral][debt]
  if (!result) {
    throw new Error('Invalid pair')
  }
  return result
}
