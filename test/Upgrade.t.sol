// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

contract TestUpgrade is BaseFixture {
    function setUp() public override {
        super.setUp();
        strategyUsers = utils.createUsers(AMOUNT_OF_USERS);
    }

    function testUpgradeStrategy() public {
        // Deploy new strategy
        AuraStrategy newStrategy = new AuraStrategy();
        // Set new strategy
        vm.prank(basedAdmin);
        auraStrategyProxy.upgradeTo(address(newStrategy));

        // Make sure the new strategy is set
        vm.prank(basedAdmin);
        assertEq(address(auraStrategyProxy.implementation()), address(newStrategy));
    }

    /// @dev Updating vault implementation and calling a function inside vault to set some arbitrary parameter
    function testUpgradeVaultToAndCall() public {
        // Deploy new proxies and simulate case for upgrading + calling
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
        AdminUpgradeabilityProxy newGoldAURAProxy =
            new AdminUpgradeabilityProxy(address(vaultImpl), address(governance), initData);
        Vault newVault = Vault(payable(newGoldAURAProxy));
        Vault newVaultImpl = new Vault();
        // New implementation will be set to newVaultImpl and treasury will be set to new addr just as an example
        bytes memory callData = abi.encodeWithSignature("setTreasury(address)", alice);
        vm.prank(governance);
        newGoldAURAProxy.upgradeToAndCall(address(newVaultImpl), callData);

        // Make sure new implementation is set and treasury is set to alice
        vm.prank(governance);
        assertEq(address(newGoldAURAProxy.implementation()), address(newVaultImpl));
        assertEq(newVault.treasury(), alice);
    }

    /// @dev Simple test for changing admin
    function testChangeAdmin() public {
        vm.prank(basedAdmin);
        auraStrategyProxy.changeAdmin(address(alice));
        vm.prank(alice);
        assertEq(auraStrategyProxy.admin(), alice);
    }
}
