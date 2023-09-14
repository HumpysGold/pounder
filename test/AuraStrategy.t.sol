// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

/// @dev Basic tests for the Vault contract
contract TestAuraStrategy is BaseFixture {
    address public constant LOCKER_REWARDS_DISTRIBUTOR = address(0xd9e863B7317a66fe0a4d2834910f604Fd6F89C6c);

    using stdStorage for StdStorage;

    uint256 public AMOUNT_OF_USERS = 10;

    function setUp() public override {
        super.setUp();
    }

    /// @dev Helper function to deposit, earn all AURA from vault into strategy
    function _setupStrategy(uint256 _depositAmount) internal {
        address payable[] memory users;
        users = utils.createUsers(AMOUNT_OF_USERS);
        for (uint256 i = 0; i < AMOUNT_OF_USERS; i++) {
            // Give alice some AURA:
            setStorage(users[i], AURA.balanceOf.selector, address(AURA), _depositAmount);
            vm.startPrank(users[i]);
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

    function testHarvestHappy(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        uint256 ppfsSnapshot = vault.getPricePerFullShare();

        _setupStrategy(_depositPerUser);
        _distributeAuraBalRewards(100_000e18);

        vm.warp(block.timestamp + 14 days);
        vm.prank(governance);
        auraStrategy.harvest();

        // Make sure ppfs in vault increased
        assertGt(vault.getPricePerFullShare(), ppfsSnapshot);
    }
}
