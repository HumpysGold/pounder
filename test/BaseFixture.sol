// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { AdminUpgradeabilityProxy } from "../src/proxy/AdminUpgradeabilityProxy.sol";
import { AuraStrategy } from "../src/AuraStrategy.sol";
import { Vault } from "../src/Vault.sol";

import "forge-std/Test.sol";
import "./Utils.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract BaseFixture is Test {
    using stdStorage for StdStorage;

    ERC20 public AURA = ERC20(address(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF));
    ERC20 public USDC = ERC20(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    ERC20 public WETH = ERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    address public constant LOCKER_REWARDS_DISTRIBUTOR = address(0xd9e863B7317a66fe0a4d2834910f604Fd6F89C6c);

    Utils internal utils;
    address payable[] internal users;
    address public alice;
    address public bob;
    address public basedAdmin;
    address public governance;
    address public treasury;
    AdminUpgradeabilityProxy public goldAURAProxy;
    AdminUpgradeabilityProxy public auraStrategyProxy;
    Vault public vaultImpl;
    AuraStrategy public auraStrategyImpl;

    // Exported for testing
    AuraStrategy public auraStrategy;
    Vault public vault;

    uint256 public constant BIPS = 10_000;
    uint256 public AMOUNT_OF_USERS = 10;
    address payable[] public strategyUsers;

    function setStorage(address _user, bytes4 _selector, address _contract, uint256 value) public {
        uint256 slot = stdstore.target(_contract).sig(_selector).with_key(_user).find();
        vm.store(_contract, bytes32(slot), bytes32(value));
    }

    /// @dev Helper function to deposit, earn all AURA from vault into strategy
    function _setupStrategy(uint256 _depositAmount) internal {
        for (uint256 i = 0; i < AMOUNT_OF_USERS; i++) {
            // Give alice some AURA:
            setStorage(strategyUsers[i], AURA.balanceOf.selector, address(AURA), _depositAmount);
            vm.startPrank(strategyUsers[i]);
            // Approve the vault to spend AURA:
            AURA.approve(address(vault), _depositAmount);
            vault.deposit(_depositAmount);
            vm.stopPrank();
        }

        vm.prank(governance);
        vault.earn();
    }

    /// @dev Helper function to distribute AURA BAL rewards to Locker so strategy has auraBAL
    /// rewards to harvest
    function _distributeAuraBalRewards(uint256 _reward) internal {
        setStorage(
            LOCKER_REWARDS_DISTRIBUTOR,
            auraStrategy.AURABAL().balanceOf.selector,
            address(auraStrategy.AURABAL()),
            100_000_000e18
        );
        vm.startPrank(LOCKER_REWARDS_DISTRIBUTOR);
        auraStrategy.LOCKER().queueNewRewards(address(auraStrategy.AURABAL()), _reward);
        vm.stopPrank();
    }

    function setUp() public virtual {
        // https://etherscan.io/block/18090274
        vm.createSelectFork("mainnet", 18_090_274);
        utils = new Utils();
        users = utils.createUsers(5);
        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
        basedAdmin = users[2];
        vm.label(basedAdmin, "Based Admin");
        governance = users[3];
        vm.label(governance, "Governance");
        treasury = users[4];
        vm.label(treasury, "Treasury");
        uint256[4] memory _feeConfig = [uint256(0), uint256(0), uint256(0), uint256(0)];
        string memory _name = "Gold Aura";
        string memory _symbol = "gAURA";
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,string,string,uint256[4])",
            address(AURA),
            governance, // governance
            address(1337), //  keeper
            address(1337), // guardian
            treasury,
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
        vm.prank(governance);
        vault.setStrategy(address(auraStrategy));
    }
}
