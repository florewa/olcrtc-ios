#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

command -v swift >/dev/null 2>&1 || {
	echo "Required command not found: swift" >&2
	exit 1
}

swift test --package-path "$ROOT_DIR" --parallel
