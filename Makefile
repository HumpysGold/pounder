-include .env

# Forge Scripts

production-deployment:
	forge script script/ProductionWireUpDeployment.s.sol --rpc-url https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY} --broadcast --etherscan-api-key ${ETHERSCAN_TOKEN} --verify

dryrun-production-deployment:
	forge script script/ProductionWireUpDeployment.s.sol --rpc-url https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}

testnet-deployment:
	forge script script/ProductionWireUpDeployment.s.sol --rpc-url https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY_SEPOLIA} --broadcast --etherscan-api-key ${ETHERSCAN_TOKEN} --verify