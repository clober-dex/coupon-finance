import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { hardhat } from 'viem/chains'

let HRE: HardhatRuntimeEnvironment | undefined
export const getHRE = (): HardhatRuntimeEnvironment => {
  if (!HRE) {
    HRE = require('hardhat')
  }
  return HRE as HardhatRuntimeEnvironment
}

export const liveLog = (...data: any[]): void => {
  if (getHRE().network.name !== hardhat.name) {
    console.log(...data)
  }
}

export interface ConvertOptions {
  ignoreTrailingZeros?: boolean
}

export function bigIntToStringWithDecimal(value: bigint, decimalPlaces: number, options?: ConvertOptions): string {
  const stringValue = value.toString()
  const length = stringValue.length

  // If the value is smaller than the desired decimal places,
  // pad with zeros to the left.
  const paddedValue = length < decimalPlaces ? '0'.repeat(decimalPlaces - length) + stringValue : stringValue

  // Insert the decimal point at the appropriate position.
  let result = `${paddedValue.slice(0, -decimalPlaces) || '0'}.${paddedValue.slice(-decimalPlaces)}`

  // Ignore trailing zeros if specified in options.
  if (options?.ignoreTrailingZeros) {
    const regex = /\.?0+$/
    result = result.replace(regex, '')
  }

  return result
}

export const convertToDateString = (utc: number): string => {
  return new Date(utc * 1000).toLocaleDateString('ko-KR', {
    year: '2-digit',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

export const sleep = (ms: number): Promise<void> => {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
