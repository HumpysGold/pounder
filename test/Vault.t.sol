// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

/// @dev Basic tests for the Vault contract
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

        // Check that there is balance available for strategy to borrow, 95% should be available
        uint256 approxAvailable = AURA.balanceOf(address(vault)) * vault.toEarnBps() / BIPS;
        assertEq(vault.available(), approxAvailable);
    }

    function testWithdraw(uint256 _depositAmount) public {
        vm.assume(_depositAmount > 1e18);
        vm.assume(_depositAmount < 100_000_000e18);
        // Give alice some AURA:
        setStorage(alice, AURA.balanceOf.selector, address(AURA), _depositAmount);
        vm.startPrank(alice);
        // Approve the vault to spend AURA:
        AURA.approve(address(vault), _depositAmount);
        vault.deposit(_depositAmount);
        vm.stopPrank();
        // Now withdraw from vault and as alice is single depositor, she should get all AURA back
        vm.startPrank(alice);
        vault.withdraw(_depositAmount * 1e18 / vault.getPricePerFullShare());
        vm.stopPrank();
        assertEq(AURA.balanceOf(address(vault)), 0);
        assertEq(AURA.balanceOf(address(alice)), _depositAmount);
        // Treasury got nothing because fees are 0 by default:
        assertEq(vault.balanceOf(treasury), 0);
    }

    function testWithdrawWithFees(uint256 _depositAmount, uint256 _fee) public {
        vm.assume(_fee > 1);
        vm.assume(_fee < 200);
        vm.assume(_depositAmount > 1e18);
        vm.assume(_depositAmount < 100_000_000e18);
        // Give alice some AURA:
        setStorage(alice, AURA.balanceOf.selector, address(AURA), _depositAmount);
        vm.prank(governance);
        vault.setWithdrawalFee(_fee);
        vm.startPrank(alice);
        // Approve the vault to spend AURA:
        AURA.approve(address(vault), _depositAmount);
        vault.deposit(_depositAmount);
        vm.stopPrank();
        // Now withdraw from vault and as alice is single depositor, she should get all AURA back
        vm.startPrank(alice);
        vault.withdraw(_depositAmount * 1e18 / vault.getPricePerFullShare());
        vm.stopPrank();
        uint256 _approximateFee = _depositAmount * _fee / BIPS;
        assertEq(AURA.balanceOf(address(alice)), _depositAmount - _approximateFee);

        // Make sure fees are in treasury
        assertEq(vault.balanceOf(treasury) * vault.getPricePerFullShare() / 1e18, _approximateFee);
    }

    function testWithdrawAll(uint256 _depositAmount) public {
        vm.assume(_depositAmount > 1e18);
        vm.assume(_depositAmount < 100_000_000e18);
        // Give alice some AURA:
        setStorage(alice, AURA.balanceOf.selector, address(AURA), _depositAmount);
        vm.startPrank(alice);
        // Approve the vault to spend AURA:
        AURA.approve(address(vault), _depositAmount);
        vault.deposit(_depositAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.withdrawAll();
        vm.stopPrank();
        assertEq(AURA.balanceOf(address(vault)), 0);
        assertEq(AURA.balanceOf(address(alice)), _depositAmount);
    }

    function testCantDepositWhenPaused() public {
        uint256 amountToDeposit = 1000e18;
        setStorage(alice, AURA.balanceOf.selector, address(AURA), amountToDeposit);
        // Pause deposits
        vm.prank(governance);
        vault.pauseDeposits();
        vm.startPrank(alice);
        // Approve the vault to spend AURA:
        AURA.approve(address(vault), amountToDeposit);
        vm.expectRevert("pausedDeposit");
        vault.deposit(amountToDeposit);
        vm.stopPrank();

        // Unpause and let alice deposit
        vm.prank(governance);
        vault.unpauseDeposits();

        vm.prank(alice);
        vault.deposit(amountToDeposit);

        assertGt(vault.balanceOf(alice), 0);
    }
}
