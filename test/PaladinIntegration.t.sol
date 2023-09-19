// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";
import { IExtraRewardsMultiMerkle } from "../src/interfaces/IExtraRewardsMultiMerkle.sol";

/// @dev Integration tests to directly communicate with Paladin merkle tree
contract PaladinIntegration is BaseFixture {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        strategyUsers = utils.createUsers(AMOUNT_OF_USERS);
    }

    // existing recipient on mainnet tree root to simulate Paladin rewards
    address payable public CLAIMER = payable(0x99AfD53f807766A8B98400B0C785E500c041F32B);
    address payable public CLAIMER_MULTI = payable(0x19124Ee4114B0444535eE57b30118CBD1Ca11eDA);
    /////////////////////////////////////////////////////////////////////////////
    ///////                  Paladin rewards harvest                        /////
    /////////////////////////////////////////////////////////////////////////////

    /// @dev Integration test for Paladin rewards harvest
    function testHarvestPaladinHappy() public {
        uint256 _depositPerUser = 100_000e18;
        _setupStrategy(_depositPerUser);

        // inject bytecode for mirroring of Aura strategy behaviour
        vm.etch(CLAIMER, address(auraStrategy).code);
        vm.store(
            address(CLAIMER),
            bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1),
            bytes32(uint256(uint160(basedAdmin)))
        );
        vm.store(
            address(CLAIMER),
            bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1),
            bytes32(uint256(uint160(address(auraStrategyImpl))))
        );
        // Overriding vault address by offsetting the storage slot by 102
        vm.store(address(CLAIMER), bytes32(uint256(102)), bytes32(uint256(uint160(auraStrategy.vault()))));
        // Inject vault addr into strategy
        vm.store(address(vault), bytes32(uint256(255)), bytes32(uint256(uint160(address(CLAIMER)))));
        // Inject want addr into strategy
        vm.store(address(CLAIMER), bytes32(uint256(101)), bytes32(uint256(uint160(address(AURA)))));
        // Snapshot ppfs:
        uint256 ppfsSnapshot = vault.getPricePerFullShare();
        // https://etherscan.io/tx/0x4e7e0ad13c10ab0a1e6f59c8238f8641816a551d15311d00e5b13b53d39bf714
        bytes32[] memory proof = new bytes32[](6);
        proof[0] = 0x85022fb07bc9f312e14b9aa9a98643e9a7e54f07b22238a8900ee68a0ce068e9;
        proof[1] = 0x8dd801e563622ae0a2a973e8d151f209f076f833c47642c13ebcfaef49b0a06b;
        proof[2] = 0x30036b1d84d1f75b0f1970d021941d0624b809019117f8a1dc6559bbee52f8de;
        proof[3] = 0x68e676fedeb6750f127f52d6dddc0ff27e4c1e5e77cb5da1c774496f98332339;
        proof[4] = 0x37853cce97340c343960af4aa25917754e858fb192ef3f2308c46986d61a7ea5;
        proof[5] = 0xcffdd8c5e040fe25f4d858f7bf9c91d95d3f63cc0ed3b22b4135e3381a5c65cf;
        IExtraRewardsMultiMerkle.ClaimParams[] memory paladinClaimParams = new IExtraRewardsMultiMerkle.ClaimParams[](1);
        paladinClaimParams[0] = IExtraRewardsMultiMerkle.ClaimParams({
            token: address(USDC),
            index: 37,
            amount: 333_826_841,
            merkleProof: proof
        });
        vm.prank(governance);
        AuraStrategy(CLAIMER).harvestPaladinDelegate(paladinClaimParams);
        // Make sure ppfs increased:
        assertGt(vault.getPricePerFullShare(), ppfsSnapshot);
    }
}
