# NTT CLI

Detailed Documentation here: https://docs.wormhole.com/wormhole/native-token-transfers/deployment

### Installation

Dependencies:

- Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Install [Bun](https://bun.sh/)

Install the NTT CLI:
```bash
curl -fsSL https://raw.githubusercontent.com/wormhole-foundation/example-native-token-transfers/main/cli/install.sh | bash
```

Verify the NTT CLI is installed:
```bash
ntt --version
```

### Updating

To update an existing NTT CLI installation, run:
```bash
ntt update
```

NTT CLI installations and updates will always pick up the latest tag with name `vX.Y.Z+cli` and verify that the underlying commit is included in main.

For local development, you can update your CLI version from a specific branch or install from a local path.

To install from a specific branch, run:
```bash
ntt update --branch foo
```

To install locally, run:
```bash
ntt update --path path/to/ntt/repo
```

Git branch and local installations enable a fast iteration loop as changes to the CLI code will immediately be reflected in the running binary without having to run any build steps.
