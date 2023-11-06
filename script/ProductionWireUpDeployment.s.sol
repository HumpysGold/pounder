// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Script } from "forge-std/Script.sol";

import { AdminUpgradeabilityProxy } from "../src/proxy/AdminUpgradeabilityProxy.sol";
import { AuraStrategy } from "../src/AuraStrategy.sol";
import { Vault } from "../src/Vault.sol";

import { ERC20WantMock } from "../test/mocks/token/ERC20WantMock.sol";

/// @notice Deploys all infrastructure in the following order:
/// 1. {Vault}
/// 2. {AdminUpgradeabilityProxy} - proxy for vault
/// 3. {AuraStrategy}
/// 4. {AdminUpgradeabilityProxy} - proxy for strategy
contract ProductionWireUpDeployment is Script {
    // rpcs
    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

    // want token testnet
    ERC20WantMock public testnetWant;

    // proxy vault
    AdminUpgradeabilityProxy public goldAuraVaultProxy;

    // proxy strategy
    AdminUpgradeabilityProxy public auraStrategyProxy;

    // goldenboys multisig: governance, treasury and proxy admin
    // ref: https://github.com/HumpysGold#addresses
    address public constant GOLD_MSIG = 0x941dcEA21101A385b979286CC6D6A9Bf435EB1C2;

    // token want
    // ref: https://docs.aura.finance/developers/deployed-addresses#mainnet
    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    // perf. fee gov initial consensus 15%, NOTE: define in BPS
    uint256 public constant PERFORMANCE_GOV_FEE = 1500;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // NOTE: only deployed during testnet
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            testnetWant = new ERC20WantMock();
        }

        // production setting
        uint256[4] memory vaultFeeConfig = [PERFORMANCE_GOV_FEE, uint256(0), uint256(0), uint256(0)];
        string memory vaultName = "Gold Aura";
        string memory vaultSymbol = "gAURA";

        bytes memory initVaultData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,string,string,uint256[4])",
            block.chainid == SEPOLIA_CHAIN_ID ? address(testnetWant) : AURA, // token want
            block.chainid == SEPOLIA_CHAIN_ID ? msg.sender : GOLD_MSIG, // governance
            address(1337), //  keeper. TODO: (TBD!) update with Gelato address assigned for the web3 task
            address(1337), // guardian. TODO: (TBD!) discuss which setup will be handling this role / address
            block.chainid == SEPOLIA_CHAIN_ID ? msg.sender : GOLD_MSIG, // treasury
            block.chainid == SEPOLIA_CHAIN_ID ? msg.sender : GOLD_MSIG, // strategist. NOTE: cannot be zero by default
            vaultName,
            vaultSymbol,
            vaultFeeConfig
        );

        address vaulLogic = address(new Vault());
        goldAuraVaultProxy = new AdminUpgradeabilityProxy(vaulLogic, GOLD_MSIG, initVaultData);

        bytes memory initStrategyData = abi.encodeWithSignature("initialize(address)", address(goldAuraVaultProxy));

        address strategyLogic = address(new AuraStrategy());
        auraStrategyProxy = new AdminUpgradeabilityProxy(strategyLogic, GOLD_MSIG, initStrategyData);

        // NOTE: after deployment for final wire up, governance (aka GOLD_MSIG) needs to set strategy in the vault!
        vm.stopBroadcast();
    }
}
