import { arbitrum } from '@wagmi/chains'

export const TESTNET_ID = 7777

export const SINGLETON_FACTORY = '0xce0042B868300000d44A59004Da54A005ffdcf9f'

export const CLOBER_FACTORY: { [chainId: number]: string } = {
  [arbitrum.id || TESTNET_ID]: '0x24aC0938C010Fb520F1068e96d78E0458855111D',
}

export const AAVE_V3_POOL: { [chainId: number]: string } = {
  [arbitrum.id || TESTNET_ID]: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
}

export const WRAPPED1155_FACTORY: { [chainId: number]: string } = {
  [arbitrum.id || TESTNET_ID]: '0xfcBE16BfD991E4949244E59d9b524e6964b8BB75',
}

export const TREASURY: { [chainId: number]: string } = {
  [arbitrum.id]: '0x000000000000000000000000000000000000dEaD', // TODO: change this
  [TESTNET_ID]: '0x000000000000000000000000000000000000dEaD',
}

export const TOKENS: { [chainId: number]: { [name: string]: string } } = {
  [arbitrum.id || TESTNET_ID]: {
    WETH: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    USDC: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    DAI: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    USDT: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    WBTC: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
  },
}

export const CHAINLINK_FEEDS: { [chainId: number]: { [name: string]: string } } = {
  [arbitrum.id || TESTNET_ID]: {
    WETH: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
    USDC: '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3',
    DAI: '0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB',
    USDT: '0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7',
    WBTC: '0x6ce185860a4963106506C203335A2910413708e9',
  },
}
