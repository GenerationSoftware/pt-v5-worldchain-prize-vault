# PoolTogether V5 Worldchain Prize Vault

This is a specialty prize vault for PoolTogether on World Chain that only allows accounts that have verified with a World ID to deposit and win prizes. Addresses are verified using an address book contract provided on worldchain. In addition, the owner of this vault can set a deposit limit that cannot be exceeded by verified accounts.

## Assumptions

- This vault has no yield source and will generate win chance through external contributions to the prize pool on its behalf.
- It is assumed that a single World ID can only verify one address at a time and that they must wait 3 months before verifying a new address.
- The asset of this vault will be the Worldcoin token on World Chain, which will also be the prize token of the prize pool.
- The claimer contract used for this vault is assumed to be functional and will incentivise all available prizes to be claimed.
- No assets will be directly sent to the vault without the use of a `deposit` or `mint` function. These will be lost forever if they are sent to the vault directly.
- The vault share token will not be used for any other purpose other than holding for win chance (for example, there will be no liquidity of the vault share on AMMs)

## Known Issues

- Since world IDs can verify new addresses every few months, a depositor can gain more win chance every few months by verifying a new address and depositing more with that address. This will not be addressed in this implementation.
- It is possible for a verified account to end up with more vault shares than the current max limit if they deposited prior to the vault owner lowering the max deposit limit. The owner will be aware of this issue.

## Development

### Installation

You may have to install the following tools to use this repository:

- [Foundry](https://github.com/foundry-rs/foundry) to compile and test contracts
- [direnv](https://direnv.net/) to handle environment variables
- [lcov](https://github.com/linux-test-project/lcov) to generate the code coverage report

Install dependencies:

```
npm i
forge install
```

### Env

Copy `.envrc.example` and write down the env variables needed to run this project.

```
cp .envrc.example .envrc
```

Once your env variables are setup, load them with:

```
direnv allow
```

### Compile

Run the following command to compile the contracts:

```
npm run compile
```

### Coverage

Forge is used for coverage, run it with:

```
npm run coverage
```

You can then consult the report by opening `coverage/index.html`:

```
open coverage/index.html
```

### Code quality

[Prettier](https://prettier.io) is used to format TypeScript and Solidity code. Use it by running:

```
npm run format
```

[Solhint](https://protofire.github.io/solhint/) is used to lint Solidity files. Run it with:

```
npm run hint
```

### CI

A default Github Actions workflow is setup to execute on push and pull request.

It will build the contracts and run the test coverage.

You can modify it here: [.github/workflows/coverage.yml](.github/workflows/coverage.yml)
