# GoldAURA main repo

| Coverage: [![codecov](https://codecov.io/github/HumpysGold/pounder/graph/badge.svg?token=1ESHEBGPZU)](https://codecov.io/github/HumpysGold/pounder)  | Tests: [![test](https://github.com/HumpysGold/pounder/actions/workflows/test.yml/badge.svg)](https://github.com/HumpysGold/pounder/actions/workflows/test.yml)  |
|---|---|

## What is this?
GoldAURA is the successor to Badger's graviAURA. Since graviAURA is set to sunset soon, we needed a new and improved product.

The product-market fit is straightforward: it allows Humpy to blackhole his AURA, charge performance fees, repurchase $GOLD, and burn it. That's essentially the core concept.

## Architecture
Pounder(goldAURA) draws heavy inspiration from the layout of graviAURA. It utilizes the same components with slight modifications:

1. [Badger Vault](https://github.com/Badger-Finance/badger-vaults-1.5) - for user deposits and share minting.
2. [Vested Aura Strategy](https://github.com/Badger-Finance/vested-aura/tree/main/contracts) - to harvest auraBAL rewards and delegator yields.

While the vault closely resembles the Badger vault 1.5, the aura strategy exhibits some significant distinctions:
Badger's AuraStrategy delegated to Badger's own delegate address, which was responsible for autovoting and collecting bribes from HiddenHand. After claiming rewards, Badger's techops multisig executed the sale of each claimed token through Cowswap, emitting aura/badger tokens via the Badger Merkle Tree.

Pounder, on the other hand, operates differently, at least for now:
- It delegates to the [Paladin vlAURA delegate](https://doc.paladin.vote/warden-quest/smart-contracts/extrarewardsmultimerkle) and claims rewards (usually in the form of USDC tokens) from Paladin's merkle tree deployed at `0x68378fCB3A27D5613aFCfddB590d35a6e751972C`.
- The strategy sells USDC tokens for WETH and then for AURA, implicitly increasing ppfs (performance fees).
- Subsequently, the strategy reports back to the vault, and fees are collected.

This fulfills the primary feature that graviAURA was missing: the automatic compounding of all rewards back into the vault, hence the name - Pounder.

## Other differences from Badger vault and graviAURA:
1. All brownie tests are rewritten in Forge/Solidity now
3. When sweeping/withdrawing non-AURA tokens from strategy, Vault logic won't send them to the badgertree, but to the treasury instead

## Running tests:
- Create .env file and place `ALCHEMY_API_KEY={YOUR KEY HERE}` env var there
- Run `forge test` to run test suite
