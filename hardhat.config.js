require('dotenv').config();
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

const { SEPOLIA_API_URL, ARBITRUM_API_URL, PRIVATE_KEY, ETHERSCAN_API_KEY } = process.env;

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "sepolia",
  networks: {
    hardhat: {},
    sepolia: {
      url: SEPOLIA_API_URL,
      accounts: [`0x${PRIVATE_KEY}`]
    },
    arbitrum: {
      url: ARBITRUM_API_URL,
      accounts: [`0x${PRIVATE_KEY}`]
    }
  },
  etherscan: {
    apiKey: {
      mainnet: ETHERSCAN_API_KEY,
      sepolia: ETHERSCAN_API_KEY,
    },
  },
}