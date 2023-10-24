## USDT can cause issues (and a couple other tokens)
https://github.com/HumpysGold/pounder/blob/e6a4acd2ba4294ab103025b43ea64951787179b6/src/AuraStrategy.sol#L367-L368

```solidity
            else if (reward_amount > 0) reward_token.approve(address(UNI_V2), reward_amount); // If this reverts, it may be worse

```

- Approve can revert (e.g. USDT)

- Non-zero to non-zero approve could also revert 

Also if it's non-zero such a token would cause reverts

-> You could nofix and then accept it

-> It may be best to reset approval to zero if the swap fails as well

```solidity
            try UNI_V2.swapExactTokensForTokens(reward_amount, uint256(0), path, address(this), block.timestamp)
            returns (uint256[] memory amounts) {
                emit RewardsCollected(address(reward_token), amounts[0]);
            } catch {
                // If univ2 pair wasn't found this means tokens can be swept later on
                continue;
                /// @audit approve down to zero here
            }
```

### Mitigation

use `safeApprove`
And add a way to reset approvals back to zero to the Pool (avoid rugs), or always set them back to zero


# Mitigation Review

- Pool, updated to the more capital efficient: 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274


- Moved to absolute balance changes
https://github.com/HumpysGold/pounder/blob/e6a4acd2ba4294ab103025b43ea64951787179b6/src/AuraStrategy.sol#L292-L293

```solidity
        uint256 auraBalEarned = AURABAL.balanceOf(address(this));

```

https://github.com/HumpysGold/pounder/blob/e6a4acd2ba4294ab103025b43ea64951787179b6/src/AuraStrategy.sol#L382-L383

```solidity
        uint256 wethEarned = WETH.balanceOf(address(this));

```



## Stuff you COULD trim

https://github.com/HumpysGold/pounder/blob/e6a4acd2ba4294ab103025b43ea64951787179b6/src/AuraStrategy.sol#L447-L454

```solidity

    function _getBalance() internal view returns (uint256) {
        return IVault(vault).balance();
    }

    function _getPricePerFullShare() internal view returns (uint256) {
        return IVault(vault).getPricePerFullShare();
    }
```

https://github.com/HumpysGold/pounder/blob/e6a4acd2ba4294ab103025b43ea64951787179b6/src/AuraStrategy.sol#L493-L496

```solidity
    /// @dev Can only receive ether from Hidden Hand
    receive() external payable {
        require(isClaimingBribes, "onlyWhileClaiming");
    }
```

https://github.com/HumpysGold/pounder/blob/e6a4acd2ba4294ab103025b43ea64951787179b6/src/AuraStrategy.sol#L35-L36

```solidity
    bool private isClaimingBribes;

```
