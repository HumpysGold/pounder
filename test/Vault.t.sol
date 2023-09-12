// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

contract TestVault is BaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function testSetup() public {
        assertEq(vault.symbol(), "gAURA");
        assertEq(vault.strategy(), address(auraStrategy));
        assertEq(vault.totalSupply(), 0);

        assertEq(auraStrategy.getName(), "GOLD vlAURA Voting Strategy");

        vm.startPrank(basedAdmin);
        assertEq(goldAURAProxy.admin(), basedAdmin);
        assertEq(goldAURAProxy.implementation(), address(vaultImpl));

        assertEq(auraStrategyProxy.admin(), basedAdmin);
        assertEq(auraStrategyProxy.implementation(), address(auraStrategyImpl));
        vm.stopPrank();
    }

    function testSimpleDeposit(uint256 _depositAmount) public {
        vm.assume(_depositAmount > 1e18);
        vm.assume(_depositAmount < 100_000_000e18);
        // Give alice some AURA:
        setStorage(alice, AURA.balanceOf.selector, address(AURA), _depositAmount);
        vm.startPrank(alice);
        // Approve the vault to spend AURA:
        AURA.approve(address(vault), _depositAmount);
        vault.deposit(_depositAmount);
        vm.stopPrank();

        // Make sure alice has shares now
        assertEq(vault.balanceOf(alice), _depositAmount);
        // As Alice holds 100% shares in vault, she has 100% shares as well:
        assertEq(vault.balanceOf(alice) * vault.getPricePerFullShare() / 1e18, _depositAmount);
        assertEq(vault.getPricePerFullShare(), 1e18);

        // Check total supply should be equal to alice's balance
        assertEq(vault.totalSupply(), _depositAmount);
    }
}
