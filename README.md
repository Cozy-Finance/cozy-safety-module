# Cozy Safety Module

Founders of projects need a way to manage the risk of shortfalls in their protocols and companies. Some examples:

- Lending protocol reserves or safety modules to pay out when there is bad debt, hacks, or other issues leading to insolvency (e.g. MakerDAO, Aave)
- General protocol protection to cover any losses due to hacks or exploits

Most of these projects currently implicitly back their projects with balance sheet capital or native tokens. The Cozy Safety Module protocol makes it easy for project leaders (whether teams or DAOs) to set up and manage a safety module.

## Development

### Getting Started

This repo is built using [Foundry](https://github.com/gakonst/foundry).

## Definitions and Standards

Definitions of terms used:
- `zoc`: A number with 4 decimals.
- `wad`: A number with 18 decimals.

Throughout the code the following standards are used:
- All token quantities in function inputs and return values are denominated in the same units (i.e. same number of decimals) as the underlying `asset` of the related asset pool.

