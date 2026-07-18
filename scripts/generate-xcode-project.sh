#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
