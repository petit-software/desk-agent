#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK_VERSION="2.3.0"
SDK_PATH="${PICO_SDK_PATH:-$HOME/Library/Caches/DeskAgent/pico-sdk-$SDK_VERSION}"
BUILD_DIR="$ROOT/firmware/build"
ARTIFACT_DIR="$ROOT/firmware/artifacts"

toolchain_candidates=(/Applications/ArmGNUToolchain/*/arm-none-eabi/bin(N))
if (( ${#toolchain_candidates[@]} > 0 )); then
  export PATH="${toolchain_candidates[-1]}:$PATH"
fi

for command in cmake ninja arm-none-eabi-gcc arm-none-eabi-ld git; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

if [[ ! -f "$SDK_PATH/pico_sdk_init.cmake" ]]; then
  mkdir -p "${SDK_PATH:h}"
  git clone \
    --depth 1 \
    --branch "$SDK_VERSION" \
    --recurse-submodules \
    --shallow-submodules \
    https://github.com/raspberrypi/pico-sdk.git \
    "$SDK_PATH"
fi

export PICO_SDK_PATH="$SDK_PATH"
cmake \
  -S "$ROOT/firmware" \
  -B "$BUILD_DIR" \
  -G Ninja \
  -DPICO_BOARD=pico \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --target deskagent_firmware

mkdir -p "$ARTIFACT_DIR"
cp "$BUILD_DIR/deskagent_firmware.uf2" "$ARTIFACT_DIR/DeskAgent.uf2"
echo "Built $ARTIFACT_DIR/DeskAgent.uf2"
