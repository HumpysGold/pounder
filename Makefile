-include .env

# Forge Scripts

production-deployment:
	forge script script/ProductionWireUpDeployment.s.sol --rpc-url https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY} --broadcast --etherscan-api-key ${ETHERSCAN_TOKEN} --verify

dryrun-production-deployment:
	forge script script/ProductionWireUpDeployment.s.sol --rpc-url https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY} --with-gas-price 27000000000
