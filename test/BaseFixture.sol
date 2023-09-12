// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { AdminUpgradeabilityProxy } from "../src/proxy/AdminUpgradeabilityProxy.sol";
import { AuraStrategy } from "../src/AuraStrategy.sol";
import { Vault } from "../src/Vault.sol";

import "forge-std/Test.sol";
import "./Utils.sol";

contract BaseFixture is Test {
    using stdStorage for StdStorage;

    Utils internal utils;
    address payable[] internal users;
    address public alice;
    address public bob;
    address public basedAdmin;
    AdminUpgradeabilityProxy public goldAURAProxy;
    AdminUpgradeabilityProxy public auraStrategyProxy;
    Vault public vaultImpl;
    AuraStrategy public auraStrategyImpl;

    // Exported for testing
    AuraStrategy public auraStrategy;
    Vault public vault;

    function setStorage(address _user, bytes4 _selector, address _contract, uint256 value) public {
        uint256 slot = stdstore.target(_contract).sig(_selector).with_key(_user).find();
        vm.store(_contract, bytes32(slot), bytes32(value));
    }

    function setUp() public virtual {
        // https://etherscan.io/block/18090274
        vm.createSelectFork("mainnet", 18_090_274);
        utils = new Utils();
        users = utils.createUsers(3);
        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        basedAdmin = users[2];
        vm.label(basedAdmin, "Based Admin");
        uint256[4] memory _feeConfig = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address _token = address(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
        string memory _name = "Gold Aura";
        string memory _symbol = "gAURA";
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,string,string,uint256[4])",
            _token,
            address(1337), // governance
            address(1337), //  keeper
            address(1337), // guardian
            address(1337),
            address(1337),
            _name,
            _symbol,
            _feeConfig
        );
        vaultImpl = new Vault();
        goldAURAProxy = new AdminUpgradeabilityProxy(address(vaultImpl), address(basedAdmin), initData);

        // Deploy strategy
        auraStrategyImpl = new AuraStrategy();
        initData = abi.encodeWithSignature("initialize(address)", address(goldAURAProxy));
        auraStrategyProxy = new AdminUpgradeabilityProxy(address(auraStrategyImpl), address(basedAdmin), initData);

        auraStrategy = AuraStrategy(payable(auraStrategyProxy));
        vault = Vault(payable(goldAURAProxy));
    }
}
