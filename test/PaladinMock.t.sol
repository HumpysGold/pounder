// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";

import { RewardsMerkleMock } from "./mocks/paladin/RewardsMerkleMock.sol";

import { IExtraRewardsMultiMerkle } from "../src/interfaces/IExtraRewardsMultiMerkle.sol";

/// @dev Mock tests to directly communicate with Paladin merkle tree
contract PaladinIntegration is BaseFixture {
    using stdStorage for StdStorage;

    RewardsMerkleMock public rewardsMerkleMock;

    address public constant CLAIMER = 0x1111111111111111111111111111111111111111;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant CURVE_LP = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC;

    // NOTE: generated using https://github.com/OpenZeppelin/merkle-tree
    bytes32 public constant ROOT_TOKEN_DAI = 0xabc2c32a11faf11c1d52d828837394b9b8719c86586d8225737b06c0aec9b4f5;
    bytes32 public constant ROOT_TOKEN_WBTC = 0x245bd0458f3146c45d46a56ddde6de6bedff25a981d64aacabf1eb1242384961;
    bytes32 public constant ROOT_TOKEN_USDT = 0xf8410fd5571526e3ab6f965cf662975ae9670496e13744f40ad6e2a8b8afd564;
    bytes32 public constant ROOT_TOKEN_CURVE_LP = 0xabc2c32a11faf11c1d52d828837394b9b8719c86586d8225737b06c0aec9b4f5;

    function setUp() public override {
        super.setUp();
        strategyUsers = utils.createUsers(AMOUNT_OF_USERS);

        rewardsMerkleMock = new RewardsMerkleMock();

        // send tokens to paladin merkle tree/mock
        address paladinRewardsMerkle = address(auraStrategy.PALADIN_REWARDS_MERKLE());
        deal(DAI, paladinRewardsMerkle, 100 ether);
        deal(WBTC, paladinRewardsMerkle, 0.5e8);
        deal(USDT, paladinRewardsMerkle, 100e6);
        deal(CURVE_LP, paladinRewardsMerkle, 100 ether);

        // set roots
        rewardsMerkleMock.updateRoot(DAI, ROOT_TOKEN_DAI);
        rewardsMerkleMock.updateRoot(WBTC, ROOT_TOKEN_WBTC);
        rewardsMerkleMock.updateRoot(USDT, ROOT_TOKEN_USDT);
        rewardsMerkleMock.updateRoot(CURVE_LP, ROOT_TOKEN_CURVE_LP);
    }

    function testHarvestPaladinDelegate_MultiToken() public {
        uint256 _depositPerUser = 100_000e18;
        _setupStrategy(_depositPerUser);

        // inject code in `PALADIN_REWARDS_MERKLE`
        vm.etch(address(auraStrategy.PALADIN_REWARDS_MERKLE()), address(rewardsMerkleMock).code);

        // Paladin - claim params: 3 tokens swappable, 1 token no swappable [BAL]
        IExtraRewardsMultiMerkle.ClaimParams[] memory paladinClaimParams = new IExtraRewardsMultiMerkle.ClaimParams[](4);
        paladinClaimParams[0] = IExtraRewardsMultiMerkle.ClaimParams({
            token: DAI,
            index: 0,
            amount: 100 ether,
            merkleProof: new bytes32[](0)
        });
        paladinClaimParams[1] = IExtraRewardsMultiMerkle.ClaimParams({
            token: WBTC,
            index: 0,
            amount: 0.5e8,
            merkleProof: new bytes32[](0)
        });
        paladinClaimParams[2] = IExtraRewardsMultiMerkle.ClaimParams({
            token: USDT,
            index: 0,
            amount: 100e6,
            merkleProof: new bytes32[](0)
        });
        paladinClaimParams[3] = IExtraRewardsMultiMerkle.ClaimParams({
            token: CURVE_LP,
            index: 0,
            amount: 100 ether,
            merkleProof: new bytes32[](0)
        });

        // Snapshot ppfs:
        uint256 ppfsSnapshot = vault.getPricePerFullShare();

        vm.prank(governance);
        auraStrategy.harvestPaladinDelegate(paladinClaimParams);

        // Make sure that EURS got idle in the strategy as it could not be swapped
        assertEq(ERC20(CURVE_LP).balanceOf(address(auraStrategy)), 100 ether);
        // Make sure ppfs increased:
        assertGt(vault.getPricePerFullShare(), ppfsSnapshot);
    }
}
