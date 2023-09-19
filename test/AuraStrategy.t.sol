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

    /// @dev Manually call reinvest when aura lock expired and wasn't reinvested automatically for some reason
    function testStrategyManualReinvest(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        _setupStrategy(_depositPerUser);

        uint256 balanceSnapshot = auraStrategy.balanceOfPool();
        vm.warp(block.timestamp + 200 days);
        // Give strategy some additional aura to make sure it will be reinvested and to check balance after
        uint256 bonusAura = 1000e18;
        setStorage(address(auraStrategy), AURA.balanceOf.selector, address(AURA), bonusAura);

        // Reinvest manually now:
        vm.prank(governance);
        auraStrategy.reinvest();

        // Check that strategy invested all loose AURA into locker
        assertEq(auraStrategy.balanceOfPool(), balanceSnapshot + bonusAura);
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                      Manual ops tests                           /////
    /////////////////////////////////////////////////////////////////////////////

    /// @dev Setup redirection route for rewards tokens that strategy can accidentially receive
    function testSweepRewardHappy(uint96 _rewardAmount, uint16 _fee) public {
        vm.assume(_rewardAmount > 10e6);
        vm.assume(_rewardAmount < 100_000e6);

        vm.assume(_fee > 0);
        vm.assume(_fee < BIPS);

        uint256 _depositPerUser = 1000e18;
        _setupStrategy(_depositPerUser);

        // Now set rewards tokens and redirection fees
        vm.startPrank(governance);
        auraStrategy.setRedirectionToken(address(USDC), governance, _fee);
        vm.stopPrank;

        // Give some USDC to strategy:
        setStorage(address(auraStrategy), USDC.balanceOf.selector, address(USDC), _rewardAmount);

        // Sweep now:
        vm.startPrank(governance);
        auraStrategy.sweepRewardToken(address(USDC));
        vm.stopPrank();
        // Make sure USDC was transferred to governance and fee transferred to treasury
        uint256 fee = _rewardAmount * _fee / BIPS;
        assertEq(IERC20(USDC).balanceOf(treasury), fee);
        assertEq(IERC20(USDC).balanceOf(governance), _rewardAmount - fee);
    }

    /// @dev Same as above but with bulk send
    function testSweepBulkRewardHappy(uint96 _rewardAmountUSDC, uint96 _rewardAmountWETH, uint16 _fee) public {
        vm.assume(_rewardAmountUSDC > 10e6);
        vm.assume(_rewardAmountUSDC < 100_000e6);
        vm.assume(_rewardAmountWETH > 10e6);
        vm.assume(_rewardAmountWETH < 100_000e6);

        vm.assume(_fee > 0);
        vm.assume(_fee < BIPS);

        uint256 _depositPerUser = 1000e18;
        _setupStrategy(_depositPerUser);

        // Now set rewards tokens and redirection fees
        vm.startPrank(governance);
        auraStrategy.setRedirectionToken(address(USDC), governance, _fee);
        auraStrategy.setRedirectionToken(address(WETH), governance, _fee);
        vm.stopPrank;

        // Give some USDC and WETH to strategy:
        setStorage(address(auraStrategy), USDC.balanceOf.selector, address(USDC), _rewardAmountUSDC);
        setStorage(address(auraStrategy), WETH.balanceOf.selector, address(WETH), _rewardAmountWETH);

        // Sweep now:
        vm.startPrank(governance);
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);
        auraStrategy.sweepRewards(tokens);
        vm.stopPrank();

        // Make sure USDC was transferred to governance and fee transferred to treasury
        uint256 fee = _rewardAmountUSDC * _fee / BIPS;
        assertEq(IERC20(USDC).balanceOf(treasury), fee);
        assertEq(IERC20(USDC).balanceOf(governance), _rewardAmountUSDC - fee);

        // Make sure WETH was transferred to governance and fee transferred to treasury
        fee = _rewardAmountWETH * _fee / BIPS;
        assertEq(IERC20(WETH).balanceOf(treasury), fee);
        assertEq(IERC20(WETH).balanceOf(governance), _rewardAmountWETH - fee);
    }

    /// @dev Can't sweep protected token
    function testSweepRewardProtectedToken() public {
        uint256 _depositPerUser = 1000e18;
        _setupStrategy(_depositPerUser);

        vm.startPrank(governance);
        auraStrategy.setRedirectionToken(address(AURA), governance, 100);
        // Even if governance set AURA as redirection token, it should not be possible to sweep it
        vm.expectRevert("_onlyNotProtectedTokens");
        auraStrategy.sweepRewardToken(address(AURA));
        vm.stopPrank;
    }

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
