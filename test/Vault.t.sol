// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

contract TestVault is BaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function testSetup() public {
        assertEq(vault.symbol(), "gAURA");
        assertEq(vault.totalSupply(), 0);

        assertEq(auraStrategy.getName(), "GOLD vlAURA Voting Strategy");

        vm.startPrank(basedAdmin);
        assertEq(goldAURAProxy.admin(), basedAdmin);
        assertEq(goldAURAProxy.implementation(), address(vaultImpl));

        assertEq(auraStrategyProxy.admin(), basedAdmin);
        assertEq(auraStrategyProxy.implementation(), address(auraStrategyImpl));
        vm.stopPrank();
    }
}
