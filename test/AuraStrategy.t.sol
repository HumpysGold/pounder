// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

import { BaseStrategy } from "../src/BaseStrategy.sol";

/// @dev Basic tests for the Vault contract
contract TestAuraStrategy is BaseFixture {
    using stdStorage for StdStorage;

    struct TokenAmount {
        address token;
        uint256 amount;
    }

    function setUp() public override {
        super.setUp();
        strategyUsers = utils.createUsers(AMOUNT_OF_USERS);
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                      Misc                                       /////
    /////////////////////////////////////////////////////////////////////////////
    function testInitializeStrategy() public {
        AuraStrategy _newAuraStrategyImpl = new AuraStrategy();
        // Initialize and check that it is initialized
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(goldAURAProxy));
        AdminUpgradeabilityProxy _newAuraStrategyProxy = new AdminUpgradeabilityProxy(
            address(_newAuraStrategyImpl), address(basedAdmin), initData
        );
        AuraStrategy _newAuraStrategy = AuraStrategy(payable(_newAuraStrategyProxy));
        // Check that it is initialized
        assertEq(_newAuraStrategy.vault(), address(goldAURAProxy));
        assertEq(_newAuraStrategy.want(), address(AURA));

        // Check allowances for AURA and auraBAL and weth
        assertEq(
            WETH.allowance(address(_newAuraStrategy), address(_newAuraStrategy.BALANCER_VAULT())), type(uint256).max
        );
        assertEq(
            AURA_BAL.allowance(address(_newAuraStrategy), address(_newAuraStrategy.BALANCER_VAULT())), type(uint256).max
        );
        assertEq(AURA.allowance(address(_newAuraStrategy), address(_newAuraStrategy.LOCKER())), type(uint256).max);
    }

    function testCannotInitProxyStrategy() public {
        AuraStrategy _newAuraStrategyImpl = new AuraStrategy();
        vm.expectRevert("Initializable: contract is already initialized");
        _newAuraStrategyImpl.initialize(address(vault));
    }

    function testGetProtectedTokens() public {
        address[] memory protectedTokens = auraStrategy.getProtectedTokens();
        assertEq(protectedTokens.length, 2);
        assertEq(protectedTokens[0], address(AURA));
        assertEq(protectedTokens[1], address(auraStrategy.AURABAL()));
    }

    function testSetWithdrawalMaxDeviationThreshold() public {
        vm.prank(governance);
        auraStrategy.setWithdrawalMaxDeviationThreshold(100);
        assertEq(auraStrategy.withdrawalMaxDeviationThreshold(), 100);
    }

    function testSetauraBalToBalEthBptMinOutBps() public {
        vm.startPrank(governance);
        auraStrategy.setAuraBalToBalEthBptMinOutBps(BIPS);
        assertEq(auraStrategy.auraBalToBalEthBptMinOutBps(), BIPS);

        vm.expectRevert("Invalid minOutBps");
        auraStrategy.setAuraBalToBalEthBptMinOutBps(BIPS + 1000);
        vm.stopPrank();
    }

    function testVersion() public {
        // Badger Vault ver 1.5
        assertEq(auraStrategy.baseStrategyVersion(), "1.5");
        // Aura strategy has 1.0 version:
        assertEq(auraStrategy.version(), "1.0");
    }

    function testIsTendable() public {
        // False as it is not used
        assertEq(auraStrategy.isTendable(), false);
    }

    function testStrategist() public {
        // Strategy strategist is same as in vault
        assertEq(auraStrategy.strategist(), vault.strategist());
    }

    function testBalanceOfRewards() public {
        // NOTE: acknowledge that no Paladin info is contained in `balanceOfRewards`
        BaseStrategy.TokenAmount memory tokenAmount = auraStrategy.balanceOfRewards()[0];

        // expecting aurabal and non-neg amount after some has being locked
        assertEq(tokenAmount.token, address(auraStrategy.AURABAL()));
        assertEq(tokenAmount.amount, 0);

        uint256 _depositPerUser = 1000e18;
        _setupStrategy(_depositPerUser);

        vm.prank(governance);
        vault.earn();

        // advanced days for aurabal rewards to accum
        vm.warp(block.timestamp + 7 days);
        tokenAmount = auraStrategy.balanceOfRewards()[0];

        // expecting non-neg amount after aura has being locked in strat
        assertGt(tokenAmount.amount, 0);
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                 Only governance function tests                  /////
    /////////////////////////////////////////////////////////////////////////////

    /// @notice Whole flow around snapshot
    function testSnapshotDelegation() public {
        bytes32 snapId = 0x62616c616e6365722e6574680000000000000000000000000000000000000000;
        address delegate = address(56);

        // Nothing was set yet
        assertEq(auraStrategy.getSnapshotDelegate(snapId), address(0));

        vm.expectRevert("onlyGovernance");
        auraStrategy.setSnapshotDelegate(snapId, delegate);

        vm.startPrank(governance);
        auraStrategy.setSnapshotDelegate(snapId, delegate);

        assertEq(auraStrategy.getSnapshotDelegate(snapId), delegate);

        vm.startPrank(governance);
        auraStrategy.clearSnapshotDelegate(snapId);

        // Ensure it was clear up properly for given id
        assertEq(auraStrategy.getSnapshotDelegate(snapId), address(0));
    }

    /// @dev it should revert in the following cases
    function test_RevertSetRedirectionToken() public {
        vm.expectRevert("Invalid token address");
        vm.startPrank(governance);
        auraStrategy.setRedirectionToken(address(0), 0);

        vm.expectRevert("Invalid redirection fee");
        vm.startPrank(governance);
        auraStrategy.setRedirectionToken(address(124), 50_000);
    }

    function testSetWithdrawalSafetyCheck() public {
        vm.expectRevert("onlyGovernance");
        auraStrategy.setWithdrawalSafetyCheck(false);

        vm.startPrank(governance);
        auraStrategy.setWithdrawalSafetyCheck(false);

        assertFalse(auraStrategy.withdrawalSafetyCheck());
    }

    function testSetProcessLocksOnReinvest() public {
        vm.expectRevert("onlyGovernance");
        auraStrategy.setProcessLocksOnReinvest(true);

        vm.startPrank(governance);
        auraStrategy.setProcessLocksOnReinvest(true);

        assertTrue(auraStrategy.processLocksOnReinvest());
    }

    /////////////////////////////////////////////////////////////////////////////
    ///////                  auraBAL rewards harvest                        /////
    /////////////////////////////////////////////////////////////////////////////

    function testHarvestWithAuraBAllRewards(uint96 _depositPerUser, uint96 _auraRewards) public {
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

    /// @dev Check that treasury get management fees when harvest reports to vault with profits
    function testHarvestWithManagementFees(uint96 _depositPerUser, uint96 _auraRewards) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);

        vm.assume(_auraRewards > 10e18);
        vm.assume(_auraRewards < 100_000e18);

        _setupStrategy(_depositPerUser);
        _distributeAuraBalRewards(_auraRewards);

        uint256 ppfsSnapshot = vault.getPricePerFullShare();
        uint256 treasurySnapshot = vault.balanceOf(treasury);
        vm.prank(governance);
        vault.setManagementFee(50);
        vm.warp(block.timestamp + 14 days);
        vm.prank(governance);
        auraStrategy.harvest();

        // Make sure ppfs in vault increased
        assertGt(vault.getPricePerFullShare(), ppfsSnapshot);
        // Make sure treasury has received management fee
        assertGt(vault.balanceOf(treasury), treasurySnapshot);
    }

    /// @dev Check that treasury get performance fees when harvest reports to vault with profits
    function testHarvestWithPerformanceGovernanceFees(uint96 _depositPerUser, uint96 _auraRewards) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);

        vm.assume(_auraRewards > 10e18);
        vm.assume(_auraRewards < 100_000e18);

        _setupStrategy(_depositPerUser);
        _distributeAuraBalRewards(_auraRewards);

        uint256 ppfsSnapshot = vault.getPricePerFullShare();
        uint256 treasurySnapshot = vault.balanceOf(treasury);
        vm.prank(governance);
        vault.setPerformanceFeeGovernance(50);
        vm.warp(block.timestamp + 14 days);
        vm.prank(governance);
        auraStrategy.harvest();

        // Make sure ppfs in vault increased
        assertGt(vault.getPricePerFullShare(), ppfsSnapshot);
        // Make sure treasury has received management fee
        assertGt(vault.balanceOf(treasury), treasurySnapshot);
    }

    /// @dev Same as above, with the only difference that no additional rewards are NOT distributed
    /// to aura locker
    function testHarvestWithoutAuraBAlRewards(uint96 _depositPerUser) public {
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
        auraStrategy.setRedirectionToken(address(USDC), _fee);
        vm.stopPrank();

        // Give some USDC to strategy:
        setStorage(address(auraStrategy), USDC.balanceOf.selector, address(USDC), _rewardAmount);

        // Sweep now:
        vm.startPrank(governance);
        auraStrategy.sweepRewardToken(address(USDC), governance);
        vm.stopPrank();
        // Make sure USDC was transferred to governance and fee transferred to treasury
        uint256 fee = _rewardAmount * _fee / BIPS;
        assertEq(IERC20(USDC).balanceOf(treasury), fee);
        assertEq(IERC20(USDC).balanceOf(governance), _rewardAmount - fee);
    }

    function testSweepRewardHappyNoFee(uint96 _rewardAmount) public {
        vm.assume(_rewardAmount > 10e6);
        vm.assume(_rewardAmount < 100_000e6);

        uint256 _fee = 0;

        uint256 _depositPerUser = 1000e18;
        _setupStrategy(_depositPerUser);

        // Now set rewards tokens and redirection fees
        vm.startPrank(governance);
        auraStrategy.setRedirectionToken(address(USDC), _fee);
        vm.stopPrank();

        // Give some USDC to strategy:
        setStorage(address(auraStrategy), USDC.balanceOf.selector, address(USDC), _rewardAmount);

        // Sweep now:
        vm.startPrank(governance);
        auraStrategy.sweepRewardToken(address(USDC), governance);
        vm.stopPrank();
        // Make sure USDC was transferred to governance received 0 fee
        assertEq(IERC20(USDC).balanceOf(treasury), _fee);
        assertEq(IERC20(USDC).balanceOf(governance), _rewardAmount);
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
        auraStrategy.setRedirectionToken(address(USDC), _fee);
        auraStrategy.setRedirectionToken(address(WETH), _fee);
        vm.stopPrank();

        // Give some USDC and WETH to strategy:
        setStorage(address(auraStrategy), USDC.balanceOf.selector, address(USDC), _rewardAmountUSDC);
        setStorage(address(auraStrategy), WETH.balanceOf.selector, address(WETH), _rewardAmountWETH);

        // Sweep now:
        vm.startPrank(governance);
        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);
        auraStrategy.sweepRewards(tokens, governance);
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
        auraStrategy.setRedirectionToken(address(AURA), 100);
        // Even if governance set AURA as redirection token, it should not be possible to sweep it
        vm.expectRevert("_onlyNotProtectedTokens");
        auraStrategy.sweepRewardToken(address(AURA), governance);
        vm.stopPrank();
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

    /// @dev Cant manual ops to process expired locks if paused
    function testManualProcessExpiredLockPaused(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        _setupStrategy(_depositPerUser);
        uint256 auraVaultSnapshot = AURA.balanceOf(address(vault));
        vm.warp(block.timestamp + 200 days);

        vm.prank(governance);
        auraStrategy.manualProcessExpiredLocks();

        vm.startPrank(governance);
        auraStrategy.pause();
        vm.expectRevert("Pausable: paused");
        auraStrategy.manualSendAuraToVault();
        vm.stopPrank();

        // Unpause and try again
        vm.startPrank(governance);
        auraStrategy.unpause();
        auraStrategy.manualSendAuraToVault();
        assertGt(AURA.balanceOf(address(vault)), auraVaultSnapshot);
        vm.stopPrank();
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
