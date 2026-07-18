#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT_DIR/scripts/generate-xcode-project.sh"
xcodebuild -workspace "$ROOT_DIR/mac/AgentMatrix.xcworkspace" -scheme AgentMatrix -configuration Debug build test
