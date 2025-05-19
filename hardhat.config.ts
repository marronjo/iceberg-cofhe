import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-foundry'
import '@nomicfoundation/hardhat-ethers'

//import './tasks'

const config: HardhatUserConfig = {
	solidity: {
		version: '0.8.26',
		settings: {
			evmVersion: 'cancun',
		},
	},
	networks: {
		anvil: {
			url: 'http://127.0.0.1:8545',
			chainId: 31337,
			accounts: [
				'0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
				'0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
				'0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
				'0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
			],
		},
	},
}

export default config
