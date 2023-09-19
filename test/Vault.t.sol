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

        // Misc checks
        assertEq(auraStrategy.version(), "1.0");
        assertEq(auraStrategy.getName(), "GOLD vlAURA Voting Strategy");

        assertEq(vault.version(), "1.5");

        // Make sure we can't initialize strategy and vault twice
        vm.expectRevert("Initializable: contract is already initialized");
        auraStrategy.initialize(address(vault));

        vm.expectRevert("Initializable: contract is already initialized");
        uint256[4] memory _feeConfig = [uint256(0), uint256(0), uint256(0), uint256(0)];
        string memory _name = "Gold Aura";
        string memory _symbol = "gAURA";
        vault.initialize(
            address(1337),
            address(1337),
            address(1337),
            address(1337),
            address(1337),
            address(1337),
            _name,
            _symbol,
            _feeConfig
        );
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

    /// @dev Simple earn test to make sure funds are transferred to strategy
    function testSimpleEarn(uint256 _depositAmount) public {
        vm.assume(_depositAmount > 10e18);
        vm.assume(_depositAmount < 100_000_000e18);
        // Give alice some AURA:
        setStorage(alice, AURA.balanceOf.selector, address(AURA), _depositAmount);
        vm.startPrank(alice);
        // Approve the vault to spend AURA:
        AURA.approve(address(vault), _depositAmount);
        vault.deposit(_depositAmount);
        vm.stopPrank();

        // Give bob some AURA:
        setStorage(bob, AURA.balanceOf.selector, address(AURA), _depositAmount);
        vm.startPrank(bob);
        // Approve the vault to spend AURA:
        AURA.approve(address(vault), _depositAmount);
        vault.deposit(_depositAmount);
        vm.stopPrank();

        // Snapshot AURA balance of strategy
        uint256 vaultBalanceBefore = AURA.balanceOf(address(vault));
        vm.prank(governance);
        vault.earn();
        // Make sure X% of AURA is transferred to strategy
        console2.log("vaultBalanceBefore", vaultBalanceBefore);
        assertFalse(AURA.balanceOf(address(vault)) == 0);
        assertEq(AURA.balanceOf(address(vault)), vaultBalanceBefore - vaultBalanceBefore * vault.toEarnBps() / BIPS);
        // Make sure aura locked in strategy and not available for withdraw
        assertEq(auraStrategy.balanceOfWant(), 0);
        // Make sure aura is locked in strategy
        assertEq(auraStrategy.balanceOfPool(), vaultBalanceBefore * vault.toEarnBps() / BIPS);
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                      Manual ops tests                           /////
    /////////////////////////////////////////////////////////////////////////////
    /// @dev Testing emit of non protected tokens
    function testEmitNonProtectedTokenHappy(uint256 _tokenAmount) public {
        vm.assume(_tokenAmount > 10e18);
        vm.assume(_tokenAmount < 100_000_000e18);

        // Give some non-protected tokens to strategy
        setStorage(address(auraStrategy), WETH.balanceOf.selector, address(WETH), _tokenAmount);

        // Now, vault makes a call to strategy to emit non-protected tokens
        vm.startPrank(governance);
        vault.emitNonProtectedToken(address(WETH));
        vm.stopPrank();
        // Token amount is split between treasury and strategist in case strategist fee is enabled
        // If strategist fees are disabled, treasury gets all tokens
        // Make sure all tokens given to governance and strategist:
        uint256 strategistFees = _tokenAmount * vault.performanceFeeStrategist() / BIPS;
        uint256 treasuryShare = _tokenAmount - strategistFees;

        assertEq(WETH.balanceOf(treasury), treasuryShare);
        // Strategist fees not enabled in goldAURA
        assertEq(WETH.balanceOf(governance), 0);
        assertEq(strategistFees, 0);
    }

    /// @dev Testing emit of non protected tokens should revert on attempting to emit protected tokens
    function testEmitNonProtectedTokenUnhappy(uint256 _tokenAmount) public {
        vm.assume(_tokenAmount > 10e18);
        vm.assume(_tokenAmount < 100_000_000e18);

        // Give some non-protected tokens to strategy
        setStorage(address(auraStrategy), AURA.balanceOf.selector, address(AURA), _tokenAmount);

        // Now, vault makes a call to strategy to emit non-protected tokens and it should revert because
        // AURA is protected token
        vm.startPrank(governance);
        vm.expectRevert("_onlyNotProtectedTokens");
        vault.emitNonProtectedToken(address(AURA));
        vm.stopPrank();
    }

    /// @dev Testing function that sweeps token from strategy to vault and then to governance
    function testSweepExtraTokenHappy(uint256 _tokenAmount) public {
        vm.assume(_tokenAmount > 10e18);
        vm.assume(_tokenAmount < 100_000_000e18);

        // Give some non-protected tokens to strategy
        setStorage(address(auraStrategy), WETH.balanceOf.selector, address(WETH), _tokenAmount);

        vm.startPrank(governance);
        vault.sweepExtraToken(address(WETH));
        vm.stopPrank();

        assertEq(WETH.balanceOf(governance), _tokenAmount);
        assertEq(WETH.balanceOf(address(auraStrategy)), 0);
    }

    /// @dev Same as above but with protected token should revert
    function testSweepExtraTokenUnhappy(uint256 _tokenAmount) public {
        vm.assume(_tokenAmount > 10e18);
        vm.assume(_tokenAmount < 100_000_000e18);

        // Give some non-protected tokens to strategy
        setStorage(address(auraStrategy), AURA.balanceOf.selector, address(AURA), _tokenAmount);

        // Now, vault makes a call to strategy to emit non-protected tokens and it should revert because
        // AURA is protected token
        vm.startPrank(governance);
        vm.expectRevert("No want");
        vault.sweepExtraToken(address(AURA));
        vm.stopPrank();
    }
}
