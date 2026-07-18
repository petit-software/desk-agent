# DeskAgent

DeskAgent is a macOS menu-bar app that turns Codex lifecycle events into
clear animations on a simulated or physical Waveshare RP2040 5x5 RGB matrix.
Communication stays local to the Mac and USB device. The app does not scrape the
terminal, read transcripts, or forward prompts and tool payloads.

## Current Status

The software-first vertical slice is implemented:

- Native SwiftUI menu-bar app, settings, and first-run onboarding.
- Deterministic 5x5 matrix simulator with brightness and orientation controls;
  brightness defaults to 25% and is restored across app launches.
- Virtual firmware with handshake, sequence acknowledgements, heartbeats, and
  fault injection.
- Automatic USB serial routing with simulator mirroring and fallback.
- Connected-device protocol testing from the simulator.
- Menu-bar display pause that blanks the LEDs while continuing to track Codex,
  then restores the latest state on resume.
- Bundled RP2040 UF2 firmware with guarded BOOTSEL flashing and reconnect
  verification from the Connected Device page.
- Session reducer with multi-session priority, deduplication, and stale-event
  protection.
- Standalone `agent-matrix-hook` executable and user-owned Unix datagram socket.
- Safe Codex hook installer with backups, atomic writes, idempotent merge, and
  scoped uninstall.
- Unit coverage for protocol parsing, animation frames, state reduction, hook
  normalization, virtual firmware, and configuration installation.

When a compatible USB CDC device completes the DeskAgent protocol handshake,
Codex lifecycle events are sent to the physical matrix automatically and remain
mirrored in the simulator. DeskAgent falls back to the simulator if the device
is unavailable. Factory Pico firmware is rejected as incompatible, and the
Connected Device page can install the bundled DeskAgent UF2 before reconnecting
and verifying the protocol.

## Matrix States

| State | Animation |
| --- | --- |
| Booting | White rows fill cumulatively, then clear from top to bottom |
| Disconnected | Dim white center pixel |
| Idle | Breathing cyan center pattern |
| Working | Blue and cyan star rotating clockwise |
| Needs Input | Pulsing amber exclamation mark |
| Finished | Green checkmark |
| Error | Pulsing red X |

## Requirements

- macOS 13 or later.
- Xcode with the macOS SDK.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) when regenerating the
  project (`brew install xcodegen`).

No RP2040 hardware is required to build or use the simulator.

## Connected Hardware Testing

Connect the board over USB, open **Matrix Simulator**, and choose
**Connected Device** in the test-target control. DeskAgent scans USB callout
ports, sends `AM1 HELLO`, and selects only firmware that returns a valid
`AM1 READY` response. Once connected, the state selector sends the same semantic
commands shown in the virtual preview to the physical matrix.

The default **Automatic** display target prefers a compatible physical matrix
and falls back to the simulator. Choose **Hardware** to require a physical
device, or **Simulator** to keep Codex events off the connected matrix.

If a Pico is visible but still runs factory firmware, the simulator reports that
DeskAgent firmware must be flashed. Choose **Flash Firmware**, hold BOOT, press
and release RESET, then release BOOT. The app waits for the `RPI-RP2` volume,
validates the bundled UF2, copies it, and verifies the AM1 connection after the
board restarts. A serial path alone is never treated as proof that compatible
firmware is installed.

## Firmware Build

The signed app build bundles `firmware/artifacts/DeskAgent.uf2`. Rebuild that
artifact after firmware changes:

```sh
brew install cmake ninja
brew install --cask gcc-arm-embedded
./scripts/build-firmware.sh
```

The build script uses Raspberry Pi Pico SDK `2.3.0` from
`~/Library/Caches/DeskAgent` by default. Set `PICO_SDK_PATH` to use another SDK
checkout.

## Build and Run

Generate the Xcode project and open the workspace:

```sh
./scripts/generate-xcode-project.sh
open mac/AgentMatrix.xcworkspace
```

Select the `AgentMatrix` scheme and run the app. DeskAgent appears in the
menu bar; open **Matrix Simulator** from its popover to inspect or test states.

To build and test from Terminal:

```sh
./scripts/build-mac.sh
```

The direct `xcodebuild` test command is:

```sh
xcodebuild \
  -workspace mac/AgentMatrix.xcworkspace \
  -scheme AgentMatrix \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Codex Integration

Open **Settings > Integrations** and install the Codex hooks. DeskAgent:

1. Installs the bundled helper at
   `~/Library/Application Support/AgentMatrix/bin/agent-matrix-hook`.
2. Backs up and merges handlers into `~/.codex/hooks.json`.
3. Preserves unrelated hooks and refuses to overwrite malformed JSON.
4. Requires you to open `/hooks` in Codex, review the command, and trust it.

The helper forwards only lifecycle metadata such as event type, session ID,
turn ID, working directory, and tool name. It discards prompts, source code,
tool input, tool output, and transcript content.

## Repository Layout

```text
docs/                       Implementation specification
firmware/                   RP2040 source and bundled release UF2
mac/AgentMatrixApp/         Menu-bar app and SwiftUI surfaces
mac/AgentMatrixCore/        Reducer, coordinator, IPC, and Codex installer
mac/AgentMatrixHook/        Standalone hook executable
mac/AgentMatrixProtocol/    Event, transport, wire, and animation models
mac/AgentMatrixSimulator/   Matrix renderer, transport, and virtual firmware
mac/AgentMatrixTests/       Unit tests
shared/animations.json      Cross-platform animation source
project.yml                 XcodeGen project definition
scripts/                    Project generation and build scripts
```

## Xcode Project

`AgentMatrix.xcodeproj` is generated from `project.yml`. Do not hand-edit the
project file. After creating or moving files, regenerate it:

```sh
./scripts/generate-xcode-project.sh
```

Repository documentation, scripts, shared assets, and root configuration files
are included as Xcode file groups so they remain visible in the navigator.

## Contributing

Read [AGENTS.md](AGENTS.md) before changing the project. Every SwiftUI `View`
must have an Xcode `#Preview`, and animation changes must update both
`shared/animations.json` and the generated Swift animation representation.
