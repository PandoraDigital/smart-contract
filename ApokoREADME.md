# 🤖Pandora Digital:
A next-gen community-owned DeFi, NFT and Gamification protocol.

[![audit-by-peckshield](https://user-images.githubusercontent.com/96759127/166666879-ce15cc28-4ffd-4454-aa7f-be48d0e8fac5.png)](https://github.com/peckshield/publications/blob/master/audit_reports/PeckShield-Audit-Report-Pandora-v1.0.pdf)



# Tokens:

## 1. PandoraSpirit:
- Description: Governance token (PSR).
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

# Earning:
## 6. Farming:
- Description: Stake LP token to earn reward token.
- File path: contracts\0.6.x\contracts\pool\Farming.sol

## 7. StakingV1:
- Description: Stake PSR earn PAN.
- File path: contracts\0.8.x\contracts\staking\Staking_PSR_PAN.sol

## 8. StakingV2:
- Description: Stake token to earn token.
- File path: contracts\0.8.x\contracts\staking\Staking_Token_Token.sol

## 9. TradingPool:
- Description: Swap to earn reward token.
- File path: contracts\0.6.x\contracts\pool\TradingPool.sol

## 10. Minter:
- Description: Storage minted PAN tokens from Pandorium contract.
- File path: contracts\0.8.x\contracts\others\Minter.sol
# NFT:
## 11. PandoBox:
- Description: NFT eggs can be cracked to get NFT pets.
- File path: contracts\0.8.x\contracts\nft\PandoBox.sol

## 12. DroidBot:
- Description: NFT pets are used for staking to earn USDT.
- File path: contracts\0.8.x\contracts\nft\DroidBot.sol

## 13. NFTRouter:
- Description: For users interact with NFTs: create eggs, create pets and upgrade pets.
- File path: contracts\0.8.x\contracts\nft\NFTRouter.sol

## 14. PandoAssembly: 
- Description: Stake NFT pets to earn USDT.
- File path: contracts\0.8.x\contracts\staking\PandoAssembly.sol

## 15. NftMarketplace:
- Description: Marketplace for buy and sell NFTs.
- File path: contracts\0.8.x\contracts\others\NftMarket.sol

## 16. DataStorage: 
- Description: Probabilistic information for creating eggs, creating pets or upgrading pets.
- File path: contracts\0.8.x\contracts\nft\DataStorage.sol

## 17. MarketFeeCollector:
- Description: Store fees collected from marketplace.
- File path: contracts\0.8.x\contracts\others\MarketFeeCollector.sol

## 18. PandoPool:
- Description: Store fund for NFT staking.
- File path: contracts\0.8.x\contracts\others\PandoPool.sol

## 19. Treasury:
- Description: Store fund for NFT staking.
- File path: contracts\0.6.x\contracts\treasury\Treasury.sol

# Gamification:
## 20. PandoPot:
- Description: Jackpot. Users can win Jackpot when creating eggs, creating pets or in trade mining leaderboard.
- File path: contracts\0.8.x\contracts\jackpot\PandoPot.sol

## 21. Referral:
- Description: Invite friends to earn more.
- File path: contracts\0.8.x\contracts\others\Referral.sol

# Oracle:
## 22. PairOracle:
- Description: Price feed for a token. Based on time-weighted average prices (TWAPs). See more: https://docs.uniswap.org/protocol/V2/concepts/core-concepts/oracles
- File path: contracts\0.8.x\contracts\others\PairOracle.sol

## 23. PSROracle:
- Description: Price feed for PSR token.
- File path: contracts\0.6.x\contracts\oracle\PSROracle.sol

## 24. PANOracle:
- Description: Price feed for PAN token.
- File path: contracts\0.6.x\contracts\oracle\PANOracle.sol

## 25. WBNBOracle:
- Description: Price feed for WBNB token.
- File path: contracts\0.6.x\contracts\oracle\WBNBOracle.sol

# Private Sale:
## 26. Lock:
- Description: Contract is used for private sale.
- File path: contracts\0.8.x\contracts\others\Lock.sol

# PSR IDO:
## 27. Presale:
- Description: Contract is used for PSR token public sale: register, commit and claim at TGE.
- File path: contracts\0.8.x\contracts\ido\Presale.sol

## 28. Verifier:
- Description: Contract is used for verifying user when claim PSR token.
- File path: contracts\0.8.x\contracts\ido\Verifier.sol

