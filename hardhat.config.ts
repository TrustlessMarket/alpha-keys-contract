import "@nomiclabs/hardhat-ethers"
import '@nomiclabs/hardhat-etherscan'
import "@typechain/hardhat"
import "hardhat-contract-sizer"
import "hardhat-dependency-compiler"
import "hardhat-gas-reporter"
import { HardhatUserConfig } from "hardhat/config"

const config: HardhatUserConfig = {
    solidity: {
        version: '0.8.19',
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,
        },
    },
    etherscan: {},
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true,
        },
        local: {
            allowUnlimitedContractSize: true,
            url: "http://127.0.0.1:8545",
        },
    },
    dependencyCompiler: {
        // We have to compile from source since UniswapV3 doesn't provide artifacts in their npm package
        paths: [
            "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol",
            "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol",
        ],
    },
    contractSizer: {
        // max bytecode size is 24.576 KB
        alphaSort: true,
        runOnCompile: true,
        disambiguatePaths: true,
        except: ["@openzeppelin/", "@uniswap/", "test/", "mock/"],
    },
    gasReporter: {
        enabled: false,
        excludeContracts: ["test"],
    },
    typechain: {
        outDir: 'typechain',
        target: 'ethers-v5',
    },
}

export default config
