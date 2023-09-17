// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import { IExtraRewardsMultiMerkle } from "../src/interfaces/IExtraRewardsMultiMerkle.sol";

interface IAuraStrategy {
    function governance() external view returns (address);
    function want() external view returns (address);
    function admin() external view returns (address);
}

/// @dev Basic tests for the Vault contract
contract TestAuraStrategy is BaseFixture {
    address public constant LOCKER_REWARDS_DISTRIBUTOR = address(0xd9e863B7317a66fe0a4d2834910f604Fd6F89C6c);
    // existing recipient on mainnet tree root to simulate Paladin rewards
    address payable public CLAIMER = payable(0x99AfD53f807766A8B98400B0C785E500c041F32B);
    address payable public CLAIMER_MULTI = payable(0x19124Ee4114B0444535eE57b30118CBD1Ca11eDA);
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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

    /// @dev Helper function to distribute AURA BAL rewards to Locker so strategy has auraBAL
    /// rewards to harvest
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
    ///////                  Paladin rewards harvest                        /////
    /////////////////////////////////////////////////////////////////////////////
    function testHarvestPaladinHappy(uint96 _depositPerUser) public {
        vm.assume(_depositPerUser > 10e18);
        vm.assume(_depositPerUser < 100_000e18);
        _setupStrategy(_depositPerUser);

        // inject bytecode for mirroring of Aura strategy behaviour
        vm.etch(CLAIMER, address(auraStrategy).code);

        // enforces storage slots of rewards sc's
        vm.prank(IAuraStrategy(CLAIMER).admin());
        //
        // https://etherscan.io/tx/0x4e7e0ad13c10ab0a1e6f59c8238f8641816a551d15311d00e5b13b53d39bf714
        bytes32[] memory proof = new bytes32[](6);
        proof[0] = 0x85022fb07bc9f312e14b9aa9a98643e9a7e54f07b22238a8900ee68a0ce068e9;
        proof[1] = 0x8dd801e563622ae0a2a973e8d151f209f076f833c47642c13ebcfaef49b0a06b;
        proof[2] = 0x30036b1d84d1f75b0f1970d021941d0624b809019117f8a1dc6559bbee52f8de;
        proof[3] = 0x68e676fedeb6750f127f52d6dddc0ff27e4c1e5e77cb5da1c774496f98332339;
        proof[4] = 0x37853cce97340c343960af4aa25917754e858fb192ef3f2308c46986d61a7ea5;
        proof[5] = 0xcffdd8c5e040fe25f4d858f7bf9c91d95d3f63cc0ed3b22b4135e3381a5c65cf;
        IExtraRewardsMultiMerkle.ClaimParams[] memory paladinClaimParams = new IExtraRewardsMultiMerkle.ClaimParams[](1);
        paladinClaimParams[0] =
            IExtraRewardsMultiMerkle.ClaimParams({ token: USDC, index: 37, amount: 333_826_841, merkleProof: proof });

        //        vm.prank(AuraStrategy(CLAIMER).governance());
        AuraStrategy(CLAIMER).harvestPaladinDelegate(paladinClaimParams);
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
}
