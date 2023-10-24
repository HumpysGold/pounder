# Operational Risks!

## Remember first depositor attack

https://code4rena.com/reports/2022-04-badger-citadel#h-03-stakedcitadel-depositors-can-be-attacked-by-the-first-depositor-with-depressing-of-vault-token-denomination

### Mitigation

Seed the Vault with at least 1e18 as part of deployment process

## Complimentary Mit Review
Hey Alex:
Went through all points again.


## Self rekt with widrawal 20 BIPs - set withdrawalMaxDeviationThreshold  to 0

https://github.com/HumpysGold/pounder/blob/b10152ec4348215632a4637037a6512a1b26540d/src/BaseStrategy.sol#L29-L30

```solidity
    uint256 public withdrawalMaxDeviationThreshold; // max allowed slippage when withdrawing

```

Verified.

## Harvest Monitoring is ignoring Paladin Yield - should be fine because it will be used specifically for auraBAL harvest, not for merkle tree rewards which is more a manual work to collect merkle proof

Acknowledged.


I don't believe there's a simple way to solve this, showing historical yields after the fact may be the simplest path forward.


## Using 50-50 pools for better slippage

https://github.com/HumpysGold/pounder/blob/b10152ec4348215632a4637037a6512a1b26540d/src/AuraStrategy.sol#L57

```solidity
bytes32 public constant AURA_ETH_POOL_ID = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;
```

Verified.

## Weth-usdc pair on univ2 should be fine, but I will monitor it and upgrade if it's suboptimal

Acknowledged.


## Reinvest removed

Verified.


### Remove these as well

https://github.com/HumpysGold/pounder/blob/b10152ec4348215632a4637037a6512a1b26540d/src/AuraStrategy.sol#L141-L145

```solidity
    /// @dev Should we processExpiredLocks during reinvest?
    function setProcessLocksOnReinvest(bool newProcessLocksOnReinvest) external {
        _onlyGovernance();
        processLocksOnReinvest = newProcessLocksOnReinvest;
    }
```

https://github.com/HumpysGold/pounder/blob/b10152ec4348215632a4637037a6512a1b26540d/src/AuraStrategy.sol#L30-L31

```solidity
    // If nothing is unlocked, processExpiredLocks will revert
    bool public processLocksOnReinvest;
```



## Unused storage vars removed


## Don't wanna remove safemath to reduce amnt of changes

Acknowledged.

While it's easy to frown upon such nofix, it ultimately costs close to nothing, imo not a big deal

## sweepExtraToken and sweepRewards: I think I should keep both of them alive to allow both strategist and gov to sweep

Acknowledged.

Let me know which one you end up using!

Everything else is ack and I don't wanna change certain things to pay the tribute to the work done on Badger Vaults 1.5 🙂


# New Findings

## QA - You don't need initializable here

https://github.com/HumpysGold/pounder/blob/b10152ec4348215632a4637037a6512a1b26540d/src/AccessControl.sol#L15-L16

```solidity
contract AccessControl is Initializable {

```

Removing it has no change

That's because AccessControl is technically abstract and Vault will inherit it


## QA - Gap Math Looks off for strategy

https://github.com/HumpysGold/pounder/blob/b10152ec4348215632a4637037a6512a1b26540d/src/BaseStrategy.sol#L396-L397

```solidity
    uint256[49] private __gap;

```

Some projects like to count the slots as a way to ensure the contract has at most 50

This doesn't look like the case, you can change it back to 50 and avoid false positive bugs and also know that 50 is the default

For upgrades, you must have a way to compare storage slots (check `cast`) + fuzz testing
