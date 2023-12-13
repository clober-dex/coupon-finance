import { task } from 'hardhat/config'
import { hardhat } from 'viem/chains'
import { Address, zeroAddress } from 'viem'
import { ASSETS, CHAINLINK_FEEDS, TOKENS, getDeployedAddress, bigIntToStringWithDecimal, liveLog } from '../utils'

task('oracle:set-feed')
  .addParam('asset', 'the name of the asset')
  .setAction(async ({ asset }, hre) => {
    const oracle = await hre.viem.getContractAt('CouponOracle', await getDeployedAddress('CouponOracle'))
    const chainId = hre.network.config.chainId ?? hardhat.id
    const token = ASSETS[chainId][asset]
    const feeds = CHAINLINK_FEEDS[chainId][asset]
    const transactionHash = await oracle.write.setFeeds([[token], [feeds]])
    liveLog('Set feed at tx', transactionHash)
  })

task('oracle:set-feeds').setAction(async (taskArgs, hre) => {
  const oracle = await hre.viem.getContractAt('CouponOracle', await getDeployedAddress('CouponOracle'))
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens: Address[] = []
  const feeds: Address[][] = []
  const keys = Object.keys(ASSETS[chainId])
  keys.forEach((key) => {
    tokens.push(TOKENS[chainId][key])
    feeds.push(CHAINLINK_FEEDS[chainId][key])
    tokens.push(ASSETS[chainId][key])
    feeds.push(CHAINLINK_FEEDS[chainId][key])
  })
  tokens.push(zeroAddress)
  feeds.push(CHAINLINK_FEEDS[chainId].WETH)
  const transactionHash = await oracle.write.setFeeds([tokens, feeds])
  liveLog('Set feeds at tx', transactionHash)
})

task('oracle:list-feeds').setAction(async (taskArgs, hre) => {
  const oracle = await hre.viem.getContractAt('CouponOracle', await getDeployedAddress('CouponOracle'))
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens = Object.values(ASSETS[chainId])
  const tokenNames = Object.keys(ASSETS[chainId])
  const feeds = await Promise.all(tokens.map((token) => oracle.read.getFeeds([token])))
  for (let i = 0; i < tokens.length; i++) {
    liveLog(`${tokenNames[i]}(${tokens[i]}): ${feeds[i]}`)
  }
})

task('oracle:list-prices').setAction(async (taskArgs, hre) => {
  const oracle = await hre.viem.getContractAt('CouponOracle', await getDeployedAddress('CouponOracle'))
  const chainId = hre.network.config.chainId ?? hardhat.id
  const tokens: Address[] = []
  const tokenNames: string[] = []
  const keys = Object.keys(ASSETS[chainId])
  keys.forEach((key) => {
    tokens.push(TOKENS[chainId][key])
    tokenNames.push(key)
    tokens.push(ASSETS[chainId][key])
    tokenNames.push(key + ' Sub')
  })
  tokens.push(zeroAddress)
  tokenNames.push('ETH')
  const prices = await Promise.all(tokens.map((token) => oracle.read.getAssetPrice([token])))
  for (let i = 0; i < tokens.length; i++) {
    liveLog(`${tokenNames[i]}(${tokens[i]}): ${bigIntToStringWithDecimal(prices[i], 8, { ignoreTrailingZeros: true })}`)
  }
})
