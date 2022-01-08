# 🤖Pandora Digital:
A next-gen community-owned DeFi, NFT and Gamification protocol.

# Tokens:

## 1. PandoraSpirit:
- Description: Governance token (SPR).
- File path: contracts\0.8.x\contracts\token\PandoraSpirit.sol

## 2. Pandorium:
- Description: Reward token (PAN).
- File path: contracts\0.8.x\contracts\token\Pandorium.sol

# AMM:

## 3. SwapFactory:
- Description: Manage all liquidity pools.
- File path: contracts\0.6.x\contracts\swap\SwapFactory.sol

## 4. SwapRouter:
- Description: For user interact with Factory: swap or add liquidity.
- File path: contracts\0.6.x\contracts\swap\SwapRouter.sol

## 5. SwapPair:
- Description: liquidity pool for a token pair.
- File path: contracts\0.6.x\contracts\swap\SwapPair.sol

# Farming:
## 6. Farming:
- Description: Stake LP token to earn reward token.
- File path: contracts\0.6.x\contracts\pool\Farming.sol

## 7. Staking:
- Description: Stake an token to earn another token.
- File path: contracts\0.8.x\contracts\staking\Staking.sol

## 8. TradingPool:
- Description: Swap to earn reward token.
- File path: contracts\0.6.x\contracts\pool\TradingPool.sol

## 9. Minter:
- Description: Storage minted PAN tokens from Pandorium contract.
- File path: contracts\0.8.x\contracts\others\Minter.sol
# NFT:
## 10. PandoBox:
- Description: NFT eggs can be cracked to get NFT pets.
- File path: contracts\0.8.x\contracts\nft\PandoBox.sol

## 11. DroidBot:
- Description: NFT pets are used for staking to earn USDT.
- File path: contracts\0.8.x\contracts\nft\DroidBot.sol

## 12. NFTRouter:
- Description: For users interact with NFTs: create eggs, create pets and upgrade pets.
- File path: contracts\0.8.x\contracts\nft\NFTRouter.sol

## 13. PandoAssembly: 
- Description: Stake NFT pets to earn USDT.
- File path: contracts\0.8.x\contracts\staking\PandoAssembly.sol

## 14. NftMarketplace:
- Description: Marketplace for buy and sell NFTs.
- File path: contracts\0.8.x\contracts\others\NftMarket.sol

## 15. DataStorage: 
- Description: Probabilistic information for creating eggs, creating pets or upgrading pets.
- File path: contracts\0.8.x\contracts\nft\DataStorage.sol

## 16. MarketFeeCollector:
- Description: Store fees collected from marketplace.
- File path: contracts\0.8.x\contracts\others\MarketFeeCollector.sol

## 17. PandoPool:
- Description: Store fund for NFT staking.
- File path: contracts\0.8.x\contracts\others\PandoPool.sol

## 18. Treasury:
- Description: Store fund for NFT staking.
- File path: contracts\0.6.x\contracts\treasury\Treasury.sol

# Gamification:
## 19. PandoPot:
- Description: Jackpot. Users can win Jackpot when creating eggs, creating pets or in trade mining leaderboard.
- File path: contracts\0.8.x\contracts\jackpot\PandoPot.sol

## 20. Referral:
- Description: Invite friends to earn more.
- File path: contracts\0.8.x\contracts\others\Referral.sol

# Oracle:
## 21. PairOracle:
- Description: Price feed for a token. Based on time-weighted average prices (TWAPs). See more: https://docs.uniswap.org/protocol/V2/concepts/core-concepts/oracles
- File path: contracts\0.8.x\contracts\others\PairOracle.sol

## 22. PSROracle:
- Description: Price feed for PSR token.
- File path:contracts\0.6.x\contracts\oracle\PSROracle.sol

## 23. PANOracle:
- Description: Price feed for PAN token.
- File path:contracts\0.6.x\contracts\oracle\PANOracle.sol

### 24. WBNBOracle:
- Description: Price feed for WBNB token.
- File path:contracts\0.6.x\contracts\oracle\WBNBOracle.sol




