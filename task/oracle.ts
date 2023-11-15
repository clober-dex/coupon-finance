import { task } from 'hardhat/config'
import { ASSETS, CHAINLINK_FEEDS, TOKENS } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { getDeployedContract, waitForTx } from '../utils/contract'
import { CouponOracle } from '../typechain'
import { bn2StrWithPrecision } from '../utils/misc'

task('oracle:set-feed')
  .addParam('asset', 'the name of the asset')
  .setAction(async ({ asset }, hre) => {
    const oracle = await getDeployedContract<CouponOracle>('CouponOracle')
    const chainId = hre.network.config.chainId ?? hardhat.id
    const token = ASSETS[chainId][asset]
    const feeds = CHAINLINK_FEEDS[chainId][asset]
    const receipt = await waitForTx(oracle.setFeeds([token], [feeds]))
    console.log('Set feed at tx', receipt.transactionHash)
  })

task('oracle:set-feeds').setAction(async (taskArgs, hre) => {
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens: string[] = []
  const feeds: string[][] = []
  const keys = Object.keys(ASSETS[chainId])
  keys.forEach((key) => {
    tokens.push(TOKENS[chainId][key])
    feeds.push(CHAINLINK_FEEDS[chainId][key])
    tokens.push(ASSETS[chainId][key])
    feeds.push(CHAINLINK_FEEDS[chainId][key])
  })
  tokens.push(hre.ethers.constants.AddressZero)
  feeds.push(CHAINLINK_FEEDS[chainId].WETH)
  const receipt = await waitForTx(oracle.setFeeds(tokens, feeds))
  console.log('Set feeds at tx', receipt.transactionHash)
})

task('oracle:list-feeds').setAction(async (taskArgs, hre) => {
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens = Object.values(ASSETS[chainId])
  const tokenNames = Object.keys(ASSETS[chainId])
  const feeds = await Promise.all(tokens.map((token) => oracle.getFeeds(token)))
  for (let i = 0; i < tokens.length; i++) {
    console.log(`${tokenNames[i]}(${tokens[i]}): ${feeds[i]}`)
  }
})

task('oracle:list-prices').setAction(async (taskArgs, hre) => {
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens = Object.values(ASSETS[chainId])
  const tokenNames = Object.keys(ASSETS[chainId])
  const prices = await Promise.all(tokens.map((token) => oracle.getAssetPrice(token)))
  for (let i = 0; i < tokens.length; i++) {
    console.log(`${tokenNames[i]}(${tokens[i]}): ${bn2StrWithPrecision(prices[i], 8)}`)
  }
})
