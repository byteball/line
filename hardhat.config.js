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
    }
  }
};
