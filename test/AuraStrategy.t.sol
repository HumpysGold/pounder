// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import { IExtraRewardsMultiMerkle } from "../src/interfaces/IExtraRewardsMultiMerkle.sol";

/// @dev Basic tests for the Vault contract
contract TestAuraStrategy is BaseFixture {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        strategyUsers = utils.createUsers(AMOUNT_OF_USERS);
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                      Misc                                       /////
    /////////////////////////////////////////////////////////////////////////////
    function testGetProtectedTokens() public {
        address[] memory protectedTokens = auraStrategy.getProtectedTokens();
        assertEq(protectedTokens.length, 2);
        assertEq(protectedTokens[0], address(AURA));
        assertEq(protectedTokens[1], address(auraStrategy.AURABAL()));
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                  auraBAL rewards harvest                        /////
    /////////////////////////////////////////////////////////////////////////////
    function testHarvestWithAdditionalRewards(uint96 _depositPerUser, uint96 _auraRewards) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);

        vm.assume(_auraRewards > 10e18);
        vm.assume(_auraRewards < 100_000e18);
        // Decrease ToEarnBps so we can check that user gets more AURA than he deposited
        vm.prank(governance);
        vault.setToEarnBps(5000);

        _setupStrategy(_depositPerUser);
        _distributeAuraBalRewards(_auraRewards);

        uint256 ppfsSnapshot = vault.getPricePerFullShare();
        uint256 balanceOfPoolSnapshot = auraStrategy.balanceOfPool();

        vm.warp(block.timestamp + 14 days);
        vm.prank(governance);
        auraStrategy.harvest();

        // Make sure ppfs in vault increased
        assertGt(vault.getPricePerFullShare(), ppfsSnapshot);

        // Make sure loose aura assets were deposited back into locker
        assertGt(auraStrategy.balanceOfPool(), balanceOfPoolSnapshot);

        // Make sure increased ppfs leads to increased withdrawable amount
        vm.startPrank(strategyUsers[0]);
        vault.withdrawAll();
        assertGt(AURA.balanceOf(strategyUsers[0]), _depositPerUser);
        vm.stopPrank();
    }

    /// @dev Same as above, with the only difference that no additional rewards are NOT distributed
    /// to aura locker
    function testHarvestWithoutAdditionalRewards(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        _setupStrategy(_depositPerUser);

        uint256 ppfsSnapshot = vault.getPricePerFullShare();
        uint256 balanceOfPoolSnapshot = auraStrategy.balanceOfPool();

        vm.warp(block.timestamp + 14 days);
        vm.prank(governance);
        auraStrategy.harvest();

        // Make sure ppfs in vault increased
        assertGt(vault.getPricePerFullShare(), ppfsSnapshot);

        // Make sure loose aura assets were deposited back into locker
        assertGt(auraStrategy.balanceOfPool(), balanceOfPoolSnapshot);
    }

    /// @dev Case when vault invested 100% of AURA into strategy and it gets locked, so users cannot
    /// withdraw
    function testHarvestFullInvested(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        // Increase ToEarnBps to 100% to check that withdrawals are not possible
        vm.prank(governance);
        vault.setToEarnBps(BIPS);
        _setupStrategy(_depositPerUser);

        vm.warp(block.timestamp + 14 days);
        vm.prank(governance);
        auraStrategy.harvest();

        vm.prank(strategyUsers[0]);
        // Reverts because no locks expired yet
        vm.expectRevert("no exp locks");
        vault.withdrawAll();
    }

    /// @dev Case opposite to above, when locks expires, users can withdraw from strategy that will
    /// unlock some AURA
    function testHarvestFullInvestedButLockExpired(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        // Increase ToEarnBps to 100% to check that withdrawals are not possible
        vm.prank(governance);
        vault.setToEarnBps(BIPS);
        _setupStrategy(_depositPerUser);

        vm.warp(block.timestamp + 14 days);
        vm.prank(governance);
        auraStrategy.harvest();

        vm.warp(block.timestamp + 360 days);
        vm.prank(strategyUsers[0]);
        vault.withdrawAll();
        // Make sure user got more AURA than he deposited
        assertGt(AURA.balanceOf(strategyUsers[0]), _depositPerUser);
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                      Manual ops tests                           /////
    /////////////////////////////////////////////////////////////////////////////
    /// @dev Manual ops to process expired locks, withdraw aura from locker and send to vault
    function testManualProcessExpiredLock(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        _setupStrategy(_depositPerUser);
        // Check that strategy invested all loose AURA into locker
        assertEq(AURA.balanceOf(address(auraStrategy)), 0);
        uint256 auraVaultSnapshot = AURA.balanceOf(address(vault));
        vm.startPrank(governance);
        // Reverts because no locks expired yet
        vm.expectRevert("no exp locks");
        auraStrategy.manualProcessExpiredLocks();
        vm.stopPrank();

        vm.warp(block.timestamp + 200 days);

        vm.prank(governance);
        auraStrategy.manualProcessExpiredLocks();

        // Check AURA balance of strategy
        assertGt(AURA.balanceOf(address(auraStrategy)), 0);

        // Transfer to vault and make sure vault received it
        vm.prank(governance);
        auraStrategy.manualSendAuraToVault();

        assertGt(AURA.balanceOf(address(vault)), auraVaultSnapshot);
    }

    /// @dev Simple check that if ran with 0 AURA to transfer it would not fail
    function testManualSendToVaultShouldNotFailIfNoAura(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        _setupStrategy(_depositPerUser);
        assertEq(AURA.balanceOf(address(auraStrategy)), 0);
        uint256 auraVaultSnapshot = AURA.balanceOf(address(vault));
        vm.prank(governance);
        auraStrategy.manualSendAuraToVault();
        assertEq(AURA.balanceOf(address(vault)), auraVaultSnapshot);
    }

    /// @dev Check delegate
    function testDelegateHappy() public {
        // Setup strategy so it has some AURA to delegate
        _setupStrategy(1000e18);
        vm.startPrank(governance);
        auraStrategy.setAuraLockerDelegate(auraStrategy.PALADIN_VOTER_ETH());
        vm.stopPrank();
        assertEq(auraStrategy.getAuraLockerDelegate(), auraStrategy.PALADIN_VOTER_ETH());

        // Try to redelegate
        vm.startPrank(governance);
        auraStrategy.setAuraLockerDelegate(address(this));
        vm.stopPrank();
        assertEq(auraStrategy.getAuraLockerDelegate(), address(this));
    }

    /// @dev Should fail to delegate when no aura locked
    function testDelegateNoAURAToDelegate() public {
        vm.startPrank(governance);
        address delegatooor = auraStrategy.PALADIN_VOTER_ETH();
        vm.expectRevert("Nothing to delegate");
        auraStrategy.setAuraLockerDelegate(delegatooor);
        vm.stopPrank();
    }
}
