import { task } from 'hardhat/config'
import { AAVE_SUBSTITUTES, CHAINLINK_FEEDS } from '../utils/constants'
import { hardhat } from '@wagmi/chains'
import { getDeployedContract, waitForTx } from '../utils/contract'
import { CouponOracle } from '../typechain'
import { bn2StrWithPrecision } from '../utils/misc'

task('oracle:set-feeds').setAction(async (taskArgs, hre) => {
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens = Object.values(AAVE_SUBSTITUTES[chainId])
  const feeds = Object.keys(AAVE_SUBSTITUTES[chainId]).map((key) => {
    return CHAINLINK_FEEDS[chainId][key]
  })
  const receipt = await waitForTx(oracle.setFeeds(tokens, feeds))
  console.log('Set feeds at tx', receipt.transactionHash)
})

task('oracle:list-feeds').setAction(async (taskArgs, hre) => {
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens = Object.values(AAVE_SUBSTITUTES[chainId])
  const tokenNames = Object.keys(AAVE_SUBSTITUTES[chainId])
  const feeds = await Promise.all(tokens.map((token) => oracle.getFeed(token)))
  for (let i = 0; i < tokens.length; i++) {
    console.log(`${tokenNames[i]}(${tokens[i]}): ${feeds[i]}`)
  }
})

task('oracle:list-prices').setAction(async (taskArgs, hre) => {
  const oracle = await getDeployedContract<CouponOracle>('CouponOracle')
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens = Object.values(AAVE_SUBSTITUTES[chainId])
  const tokenNames = Object.keys(AAVE_SUBSTITUTES[chainId])
  const prices = await Promise.all(tokens.map((token) => oracle.getAssetPrice(token)))
  for (let i = 0; i < tokens.length; i++) {
    console.log(`${tokenNames[i]}(${tokens[i]}): ${bn2StrWithPrecision(prices[i], 8)}`)
  }
})
