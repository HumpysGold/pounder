# Gold Pounder Report

As with all Peer Review the report is a Best Attempt to find flaws in the system and highlight gotchas

Due to the lindy system as well as upgradeability, risk to the system is pretty low, however, upgrade risks are always a big concern to end users


The review is separate by file and where useful it shows recommendations

# Paladin Merkle

## MED / LOW - Paladin Claims can be performed on Behalf, breaking the absolute logic if WETH is a reward

https://etherscan.io/address/0x997523eF97E0b0a5625Ed2C197e61250acF4e5F1#code#F1#L132

Use Absolute USDC and WETH balances

Ultimately both tokens can be swept, but for convenience it may be best to use absolute balances, this will avoid having to sweep the tokens out

## LOW - Operational Risk of Paladin System

In contrast to BadgerTree, their proofs are "spot"

Meaning they must `freezeRoot`, then compute the new root, then allow claims again

They follow this procedure, however, keep in mind that if they simply update the root, that may allow stealing of previous rewards

2 considerations:
1) May want to monitor Paladin
2) Claiming ASAP would avoid someone else stealing the yield, so it may be best to "auto-claim" as soon as the API is updated to avoid this fairly chance scenario

## MED / LOW - USDC WETH PATH is Suboptimal - 30 BPS

https://app.1inch.io/#/1/simple/swap/USDC/WETH

https://v2.info.uniswap.org/pair/0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc

Generally suboptimal

I would think up to 30 BPS in loss until it gets fully deprecated / abandoned

vs UniV3
https://info.uniswap.org/#/tokens/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2

30 cents per unit + the fee is higher on V2

Overall it's inefficient but not a huge deal

3*10^6 * .5 * 3 /10000
$4.5k per year
on 3 Mil at 50% yield

$1k in fees if you assume 20% goes to you

# AuraStrategy.sol


## MED / LOW - Delta Risk - Just use Absolute Value - See `Paladin Claims can be performed on Behalf, breaking the absolute logic if WETH is a reward`

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L343-L344

```solidity
            uint256 wethEarned = WETH.balanceOf(address(this)).sub(wethBalanceBefore);

```

There is a latent risk of having WETH stuck in the Strategy (can be sweeped)

But there's no advantage in not processing it

You are better off performing the swap with all WETH

And if you ever want to sweep

Sweep first, then do the Harvest

Same here:
https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L395-L396

```solidity
        uint256 wethEarned = WETH.balanceOf(address(this)) - wethBalanceBefore;

```

## MED / LOW - Self-Rekt in extreme case

https://miro.com/app/board/uXjVNahPO_A=/?moveToWidget=3458764566714401759&cot=14

Due to `_withdrawSome` trying it's best and then allowing 20 BPS of loss

A caller may:
-> See unlock
-> Require up to 20BPS of tokens more than unlock
-> Trigger one unlock which reduces `max` to the amount they requested - 20BPS
-> Lose 20BPS (ppfs raises funny enough)

This has never happened as it requires a caller needing exactly that amount, causing an unlock and not being able to receive it

Changing `BaseStrategy.withdrawalMaxDeviationThreshold` to 0 should prevent this edge case scenario

### Mitigation

If this happens consider reimbursing the person

Or to prevent it, set `withdrawalMaxDeviationThreshold` to 0 as that will always cause reverts if the strategy returns less than what was asked


## MED / MEV: AURA WETH 50 50 is better, replace it

https://app.balancer.fi/#/ethereum/pool/0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274
https://app.balancer.fi/#/ethereum/pool/0xc29562b045d80fd77c69bec09541f5c16fe20d9d000200000000000000000251

0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274

Offers better swap rate, and is a one line change


## NOTES: AURABAL_BALETH_BPT_POOL_ID
Safe because stable, stable needs an insane imbalance to break

BAL_ETH_POOL_ID seems legit

AURA_ETH_POOL_ID -> Seems like there's a better one

Rest of pools are fine

Obv changes could be better but it's ok

I recommend checking every couple of months on Balancer UI to determine what the best segment pool is for around 10 / 20k

# QA - See VAULT `Sweep can bypass redirection via Vault.sweepExtraToken`

## Convenience / User Safety

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L501-L502

```solidity
        address recepient = bribesRedirectionPaths[token];

```

If you are allowing only governance, then no point in hardcoding `bribesRedirectionPaths`

Just allow passing of arbitrary value


Else allows Strategist to make the operation Less Permissioned and faster


### Same idea here

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L169-L185

```solidity
    /// @dev Function to move rewards that are not protected
    /// @notice Only not protected, moves the whole amount using _handleRewardTransfer
    /// @notice because token paths are hardcoded, this function is safe to be called by anyone
    function sweepRewardToken(address token) external nonReentrant {
        _onlyGovernance();
        _sweepRewardToken(token);
    }

    /// @dev Bulk function for sweepRewardToken
    function sweepRewards(address[] calldata tokens) external nonReentrant {
        _onlyGovernance();

        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            _sweepRewardToken(tokens[i]);
        }
    }
```


## QA - Unused, can delete

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L461-L468

```solidity
    function _getBalance() internal view returns (uint256) {
        return IVault(vault).balance();
    }

    function _getPricePerFullShare() internal view returns (uint256) {
        return IVault(vault).getPricePerFullShare();
    }

```

## QA / Low - Harvest Monitoring is ignoring Paladin Yield

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L220-L221

```solidity
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {

```

Just a gotcha, I think it's ok

You could also use the balance of WETH / USDC as part of this

## QA - Technically this can change

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L232-L237

```solidity
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = want; // AURA
        protectedTokens[1] = address(AURABAL);
        return protectedTokens;
    }
```

You could use the rewards from the AURA Locker, that said this is not expected to be that much


## L - C4-Grief - Pretty sure this can be made to revert, you can still deprecated down to dust amounts

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L262-L268

```solidity

    function _withdrawAll() internal view override {
        //NOTE: This probably will always fail unless we have all tokens expired
        require(balanceOfPool() == 0 && LOCKER.balanceOf(address(this)) == 0, "Tokens still locked");

        // Make sure to call prepareWithdrawAll before _withdrawAll
    }
```

SEE:

https://github.com/code-423n4/2022-06-badger-findings/issues/92

In a deprecation, some griefing can be performed, you can still use `manualSendAuraToVault` to make withdrawals cheap


## Comment - This is a hardcoded "peg" slippage

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L37-L38

```solidity
    uint256 public auraBalToBalEthBptMinOutBps;

```

Worth keeping in mind that this has to be tweaked based on how well or how poorly auraBAL is doing

## Unused - just delete

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L35-L36

```solidity
    bool private isClaimingBribes;

```

## Was never used - Prob just delete

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/AuraStrategy.sol#L428-L444

```solidity
    /// @dev manual function to reinvest all Aura that was locked
    function reinvest() external whenNotPaused returns (uint256) {
        _onlyGovernance();

        if (processLocksOnReinvest) {
            // Withdraw all we can
            LOCKER.processExpiredLocks(false);
        }

        // Redeposit all into vlAURA
        uint256 toDeposit = IERC20Upgradeable(want).balanceOf(address(this));

        // Redeposit into vlAURA
        _deposit(toDeposit);

        return toDeposit;
    }
```

This whole idea was never used and is pretty bad

It basically unlocks and then relocks everything

We never used it to allow the liquid locker aspect

-> This is basically:
`manualProcessExpiredLocks`
`earn` with a lower amount

Can be replicate by changing earnBPS if you ever need to

# Vault.sol

## NOTE: Sweep can bypass redirection via Vault.sweepExtraToken

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/Vault.sol#L544-L553

```solidity
    function sweepExtraToken(address _token) external {
        _onlyGovernanceOrStrategist();
        require(address(token) != _token, "No want");

        IStrategy(strategy).withdrawOther(_token);
        // Send all `_token` we have
        // Safe because `withdrawOther` will revert on protected tokens
        // Done this way works for both a donation to strategy or to vault
        IERC20Upgradeable(_token).safeTransfer(governance, IERC20Upgradeable(_token).balanceOf(address(this)));
    }
```

Redirection is set in Strategy and enforces that Governance does it

It also enforces BribeRedirection Paths and Fees (imo supreflous)

However, you can also use `sweepExtraToken` which uses `withdrawOther` as a way to sweep non-protected tokens

TL;DR `sweepRewards` and `sweepExtraToken` work in the same way, but `sweepExtraToken` can be called by the Strategist

### Recommendation

-> Chart out use cases and document them
-> Avoid gotchas

### My Recommendation

Delete most of the code in the strategy and use `sweepExtraToken`

# BaseStrategy.sol

## QA - Unused Storage Variable
https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/BaseStrategy.sol#L60-L61

# Generic Notes

# L - GOTCHA

Can only work on Mainnet

Other chains use EVM Paris which is without the Opcode PUSH0

See: https://github.com/code-423n4/2023-09-delegate/blob/main/foundry.toml


# QA

## QA - SafeMath on 8.13

Safe Math is not necessary

I'm not sure if it's worth the work to remove

## QA - Can remove the naming stuff if you know you're just writing one vault

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/Vault.sol#L181-L191


## L - Yield Gotcha

https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/Vault.sol#L217-L218

You could set to 100% so you lock and then you can manage the rest of tokens via the unlocking

Means first week is fully locked

Fun Fact:
You could keep 1 wei of token to make everything cheaper (avoids resetting of Storage)


## QA - You can pause deposit on deprecation to prevent random earns
https://github.com/HumpysGold/pounder/blob/c44f179de8da2b939d992d3f8a81c04326ba0dd7/src/Vault.sol#L561-L568

```solidity
    function earn() external {
        require(!pausedDeposit, "pausedDeposit"); // dev: deposits are paused, we don't earn as well
        _onlyAuthorizedActors();

        uint256 _bal = available();
        token.safeTransfer(strategy, _bal);
        IStrategy(strategy).earn();
    }
```

You could also block earn via another variable if you so chose it

# Quick Cheasheet around operations

# Quick Logic Around Operations

-> Deposits
-> Change / Tweak `toEarnBps` for withdrawals + Lock size (Recommend 10_000 to lock all)

-> Every X weeks -> `manualProcessExpiredLocks` - CARE: Forgetting = Slashed

-> Claim Bribes and harvest

-> Extra Tokens: Have a Strategist `sweepExtraToken` to `governance`

-> Reduce maxFees etc to low values to avoid Strategist rugging -> This may allow keeping Stragist to an EOA as they cannot do anything dangerous

----

Deprecation:

-> Stop locking by not `earn`ing

----

Keeping Lock unlcoked

-> Delay earn by a week after an unlock (check Bribes Market for cutoffs)
