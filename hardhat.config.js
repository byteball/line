require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    kava: {
      url: process.env.testnet ? 'https://evm.testnet.kava.io' : 'https://evm.kava.io',
      accounts: {
        mnemonic: process.env.mnemonic,
      }
    },
    bsc: {
      url: process.env.testnet ? "https://data-seed-prebsc-1-s1.binance.org:8545" : "https://bsc-dataseed.binance.org",
      accounts: {
        mnemonic: process.env.mnemonic,
      }
    },
    polygon: {
      url: process.env.testnet ? "https://rpc-mumbai.maticvigil.com" : "https://rpc-mainnet.maticvigil.com",
      accounts: {
        mnemonic: process.env.mnemonic,
      }
    },
  }
};
