// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { IERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

/// @dev This mock is needed for:
/// - Test multi-token scenario
/// - Test non-swappable token scenario
contract RewardsMerkleMock {
    using SafeERC20 for IERC20;

    // Storage

    /**
     * @notice Merkle Root for each token
     */
    mapping(address => bytes32) public merkleRoots;

    //Struct ClaimParams
    struct ClaimParams {
        address token;
        uint256 index;
        uint256 amount;
        bytes32[] merkleProof;
    }

    // Events

    /**
     * @notice Event emitted when an user Claims
     */
    event Claimed(address indexed rewardToken, uint256 index, address indexed account, uint256 amount);

    /**
     * @notice Event emitted when a Merkle Root is updated
     */
    event UpdateRoot(address indexed rewardToken, bytes32 merkleRoot);

    error InvalidProof();

    /**
     * @notice Claims multiple rewards for a given list
     * @dev Calls the claim() method for each entry in the claims array
     * @param account Address of the user claiming the rewards
     * @param claims List of ClaimParams struct data to claim
     */
    function multiClaim(address account, ClaimParams[] calldata claims) external {
        uint256 length = claims.length;
        for (uint256 i; i < length;) {
            claim(claims[i].token, claims[i].index, account, claims[i].amount, claims[i].merkleProof);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Claims rewards for a given token for the user
     * @dev Claims the reward for an user for the current update of the Merkle Root for the given token
     * @param token Address of the token to claim
     * @param index Index in the Merkle Tree
     * @param account Address of the user claiming the rewards
     * @param amount Amount of rewards to claim
     * @param merkleProof Proof to claim the rewards
     */
    function claim(
        address token,
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    )
        public
    {
        /// @dev we simplify here only for transfer to test multi-token scenario in mock
        // bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
        // bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        // if (!MerkleProof.verify(merkleProof, merkleRoots[token], leaf)) revert InvalidProof();

        IERC20(token).safeTransfer(account, amount);

        emit Claimed(token, index, account, amount);
    }

    /**
     * @notice Udpates the Merkle Root for a given token
     * @dev Updates the Merkle Root for a frozen token
     * @param token Address of the token
     * @param root Merkle Root
     */
    function updateRoot(address token, bytes32 root) public {
        merkleRoots[token] = root;

        emit UpdateRoot(token, root);
    }
}
