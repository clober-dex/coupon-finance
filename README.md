# Coupon Finance

[![Docs](https://img.shields.io/badge/docs-%F0%9F%93%84-blue)](https://docs.coupon.finance/)
[![CI status](https://github.com/clober-dex/coupon-finance/actions/workflows/test.yaml/badge.svg)](https://github.com/clober-dex/coupon-finance/actions/workflows/test.yaml)
[![Discord](https://img.shields.io/static/v1?logo=discord&label=discord&message=Join&color=blue)](https://discord.gg/clober)
[![Twitter](https://img.shields.io/static/v1?logo=twitter&label=twitter&message=Follow&color=blue)](https://twitter.com/CouponFinance)

Contract of Coupon Finance

## Table of Contents

- [Coupon Finance](#coupon-finance)
    - [Table of Contents](#table-of-contents)
    - [Install](#install)
    - [Usage](#usage)
        - [Unit Tests](#unit-tests)
        - [Linting](#linting)
    - [Audits](#audits)
    - [Licensing](#licensing)

## Install

To install dependencies and compile contracts:

### Prerequisites
- We use [Forge Foundry](https://github.com/foundry-rs/foundry) for test. Follow the [guide](https://github.com/foundry-rs/foundry#installation) to install Foundry.

### Installing From Source

```bash
git clone https://github.com/clober-dex/coupon-finance && cd coupon-finance
npm install
```

## Usage

### Unit tests
```bash
npm run test:forge
```

### Linting

To run lint checks:
```bash
npm run prettier:ts
npm run lint:sol
```

To run lint fixes:
```bash
npm run prettier:fix:ts
npm run lint:fix:sol
```

## Audits
Audited by [Trust](https://www.trust-security.xyz) and [HickupHH3](https://github.com/HickupHH3) from August to October 2023. All vulnerable security risks are fixed. Full reports are available [here](./audits).

## Licensing

- The primary license for Coupon Finance is the Time-delayed Open Source Software License, see [License file](LICENSE.pdf).
