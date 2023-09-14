// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

/// @dev Basic tests for the Vault contract
contract TestAuraStrategy is BaseFixture {
    address public constant LOCKER_REWARDS_DISTRIBUTOR = address(0xd9e863B7317a66fe0a4d2834910f604Fd6F89C6c);

    using stdStorage for StdStorage;

    uint256 public AMOUNT_OF_USERS = 10;

    address payable[] public strategyUsers;

    function setUp() public override {
        super.setUp();
        strategyUsers = utils.createUsers(AMOUNT_OF_USERS);
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

    /// @dev Helper function to distribute AURA BAL rewards to Locker so strategy has auraBAL rewards to harvest
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

    /// @dev Same as above, with the only difference that no additional rewards are NOT distributed to aura locker
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
}
