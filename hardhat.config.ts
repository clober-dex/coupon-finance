import path from 'path'
import fs from 'fs'

import * as dotenv from 'dotenv'
import readlineSync from 'readline-sync'
import { HardhatConfig } from 'hardhat/types'
import * as networkInfos from 'viem/chains'

import 'hardhat-deploy'
import '@nomicfoundation/hardhat-viem'
import 'hardhat-gas-reporter'
import 'hardhat-contract-sizer'
import 'hardhat-abi-exporter'
import '@nomicfoundation/hardhat-verify'

import { TESTNET_ID } from './utils'

dotenv.config()

const chainIdMap: { [key: string]: string } = {}
for (const [networkName, networkInfo] of Object.entries(networkInfos)) {
  // @ts-ignore
  chainIdMap[networkInfo.id] = networkName
}

const SKIP_LOAD = process.env.SKIP_LOAD === 'true'

if (!SKIP_LOAD) {
  const tasksPath = path.join(__dirname, 'task')
  fs.readdirSync(tasksPath)
    .filter((pth) => pth.includes('.ts'))
    .forEach((task) => {
      require(`${tasksPath}/${task}`)
    })
}

let privateKey: string
let ok: string

const getMainnetPrivateKey = () => {
  let network
  for (const [i, arg] of Object.entries(process.argv)) {
    if (arg === '--network') {
      network = parseInt(process.argv[parseInt(i) + 1])
      if (network.toString() in chainIdMap && ok !== 'Y') {
        ok = readlineSync.question(`You are trying to use ${chainIdMap[network.toString()]} network [Y/n] : `)
        if (ok !== 'Y') {
          throw new Error('Network not allowed')
        }
      }
    }
  }

  const prodNetworks = new Set<number>([networkInfos.mainnet.id, networkInfos.arbitrum.id])
  if (network && prodNetworks.has(network)) {
    if (privateKey) {
      return privateKey
    }
    const keythereum = require('keythereum')

    const KEYSTORE = './deployer-key.json'
    const PASSWORD = readlineSync.question('Password: ', {
      hideEchoBack: true,
    })
    if (PASSWORD !== '') {
      const keyObject = JSON.parse(fs.readFileSync(KEYSTORE).toString())
      privateKey = '0x' + keythereum.recover(PASSWORD, keyObject).toString('hex')
    } else {
      privateKey = '0x0000000000000000000000000000000000000000000000000000000000000001'
    }
    return privateKey
  }
  return '0x0000000000000000000000000000000000000000000000000000000000000001'
}

const config: HardhatConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.19',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
    overrides: {},
  },
  // @ts-ignore
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ARBISCAN_API_KEY ?? '',
      arbitrumGoerli: process.env.ARBISCAN_API_KEY ?? '',
    },
    customChains: [],
  },
  defaultNetwork: 'hardhat',
  networks: {
    [networkInfos.arbitrum.id]: {
      url: process.env.ARBITRUM_NODE_URL ?? networkInfos.arbitrum.rpcUrls.default.http[0],
      chainId: networkInfos.arbitrum.id,
      accounts: [getMainnetPrivateKey()],
      gas: 'auto',
      gasPrice: 100000000,
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['mainnet', 'prod'],
      companionNetworks: {},
      verify: {
        etherscan: {
          apiKey: process.env.ARBISCAN_API_KEY,
          apiUrl: 'https://api.arbiscan.io',
        },
      },
    },
    [networkInfos.arbitrumGoerli.id]: {
      url: networkInfos.arbitrumGoerli.rpcUrls.default.http[0],
      chainId: networkInfos.arbitrumGoerli.id,
      accounts: process.env.TEST_NET_PRIVATE_KEY ? [process.env.TEST_NET_PRIVATE_KEY] : [],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['testnet', 'test'],
      companionNetworks: {},
      verify: {
        etherscan: {
          apiKey: process.env.ARBISCAN_API_KEY,
          apiUrl: 'https://api-goerli.arbiscan.io',
        },
      },
    },
    [TESTNET_ID]: {
      url: process.env.TEST_NET_URL ?? '',
      chainId: TESTNET_ID,
      accounts: process.env.TEST_NET_PRIVATE_KEY ? [process.env.TEST_NET_PRIVATE_KEY] : [],
      gas: 'auto',
      gasPrice: 'auto',
      gasMultiplier: 1,
      timeout: 3000000,
      httpHeaders: {},
      live: true,
      saveDeployments: true,
      tags: ['testnet', 'test'],
      companionNetworks: {},
    },
    [networkInfos.hardhat.network]: {
      chainId: networkInfos.hardhat.id,
      gas: 20000000,
      gasPrice: 250000000000,
      gasMultiplier: 1,
      hardfork: 'shanghai',
      // @ts-ignore
      // forking: {
      //   enabled: true,
      //   url: 'ARCHIVE_NODE_URL',
      // },
      mining: {
        auto: true,
        interval: 0,
        mempool: {
          order: 'fifo',
        },
      },
      accounts: {
        mnemonic: 'loop curious foster tank depart vintage regret net frozen version expire vacant there zebra world',
        initialIndex: 0,
        count: 10,
        path: "m/44'/60'/0'/0",
        accountsBalance: '10000000000000000000000000000',
        passphrase: '',
      },
      blockGasLimit: 200000000,
      // @ts-ignore
      minGasPrice: undefined,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      allowUnlimitedContractSize: true,
      initialDate: new Date().toISOString(),
      loggingEnabled: false,
      // @ts-ignore
      chains: undefined,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  abiExporter: [
    // @ts-ignore
    {
      path: './abi',
      runOnCompile: false,
      clear: true,
      flat: true,
      only: [],
      except: [],
      spacing: 2,
      pretty: false,
      filter: () => true,
    },
  ],
  mocha: {
    timeout: 40000000,
    require: ['hardhat/register'],
  },
  // @ts-ignore
  contractSizer: {
    runOnCompile: true,
  },
}

export default config
