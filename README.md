## Development

CLT Ekubo uses [Scarb](https://docs.swmansion.com/scarb/docs) for development and testing purposes, and [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/index.html) as a toolchain to test contracts on mainnet forks.

### Prepare Environment

Simply install [Cairo and scarb](https://docs.swmansion.com/scarb/download).

### Dependencies

- scarb v2.9.2
- cairo v2.9.2
- sierra v1.6.0
- snforge v0.35.1

### Build Contracts

```bash
scarb build
```

### Test Contracts

```bash
scarb test
```
