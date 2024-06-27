#!/usr/bin/env bash

set -euo pipefail

# check that 'bun' is installed

if ! command -v bun > /dev/null; then
  echo "bun is not installed. Follow the instructions at https://bun.sh/docs/installation"
  exit 1
fi

function main {
  path=""

  # check if there's a package.json in the parent directory, with "name": "@wormhole-foundation/ntt-cli"
  if [ -f "$(dirname $0)/package.json" ] && grep -q '"name": "@wormhole-foundation/ntt-cli"' "$(dirname $0)/package.json"; then
  path="$(dirname $0)/.."
  else
    # clone to $HOME/.ntt-cli if it doesn't exist, otherwise update it
    repo_ref="$(select_repo)"
    repo="$(echo "$repo_ref" | awk '{print $1}')"
    ref="$(echo "$repo_ref" | awk '{print $2}')"
    echo "Cloning $repo $ref"

    mkdir -p "$HOME/.ntt-cli"
    path="$HOME/.ntt-cli/.checkout"

    if [ ! -d "$path" ]; then
      git clone --branch "$ref" "$repo" "$path"
    else
      pushd "$path"
      git fetch origin
      # reset hard
      git reset --hard "origin/$ref"
      popd
    fi

  fi

  install_cli "$path"
}

# function that determines which repo to clone
function select_repo {
  foundation_repo="https://github.com/wormhole-foundation/example-native-token-transfers.git"
  labs_repo="https://github.com/wormholelabs-xyz/example-native-token-transfers.git"
  # if the foundation repo has a tag of the form "vX.Y.Z+cli", use that (the latest one)
  # otherwise we'll use the 'cli' branch from the labs repo
  ref=""
  repo=""
  regex="refs/tags/v[0-9]*\.[0-9]*\.[0-9]*+cli"
  if git ls-remote --tags "$foundation_repo" | grep -q "$regex"; then
    repo="$foundation_repo"
    ref="$(git ls-remote --tags "$foundation_repo" | grep "$regex" | sort -V | tail -n 1 | awk '{print $2}')"
  else
    repo="$labs_repo"
    ref="cli"
  fi

  echo "$repo $ref"
}

# the above but as a function. takes a single argument: the path to the package.json file
# TODO: should just take the path to the repo root as an argument...
function install_cli {
  cd "$1"

  # if 'ntt' is already installed, uninstall it
  # just check with 'which'
  if which ntt > /dev/null; then
    echo "Removing existing ntt CLI"
    rm $(which ntt)
  fi

  # swallow the output of the first install
  # TODO: figure out why it fails the first time.
  bun install > /dev/null 2>&1 || true
  bun install

  # make a temporary directory

  tmpdir="$(mktemp -d)"

  # create a temporary symlink 'npm' to 'bun'

  ln -s "$(command -v bun)" "$tmpdir/npm"

  # add the temporary directory to the PATH

  export PATH="$tmpdir:$PATH"

  # swallow the output of the first build
  # TODO: figure out why it fails the first time.
  bun --bun run --filter '*' build > /dev/null 2>&1 || true
  bun --bun run --filter '*' build

  # remove the temporary directory

  rm -r "$tmpdir"

  # now link the CLI

  cd cli

  bun link

  bun link @wormhole-foundation/ntt-cli
}

main
