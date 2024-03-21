#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
TARGET=${SCRIPT_DIR}/../programs
RESULTS=$(find "${TARGET}" -name "*.rs" -type f -exec anchor idl parse -o /dev/null --file {} \; 2>&1 | grep -v 'Program module not found')
# echo $RESULTS
if [ -n "$RESULTS" ]; then
	echo "${RESULTS}"
	exit 1
fi
