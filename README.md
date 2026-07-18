# Agent Matrix

Agent Matrix is a macOS menu-bar app that turns Codex lifecycle events into
clear animations on a simulated or physical Waveshare RP2040 5x5 RGB matrix.
Communication stays local to the Mac and USB device. The app does not scrape the
terminal, read transcripts, or forward prompts and tool payloads.

## Current Status

The software-first vertical slice is implemented:

- Native SwiftUI menu-bar app, settings, and first-run onboarding.
- Deterministic 5x5 matrix simulator with brightness and orientation controls.
- Virtual firmware with handshake, sequence acknowledgements, heartbeats, and
  fault injection.
- Session reducer with multi-session priority, deduplication, and stale-event
  protection.
- Standalone `agent-matrix-hook` executable and user-owned Unix datagram socket.
- Safe Codex hook installer with backups, atomic writes, idempotent merge, and
  scoped uninstall.
- Unit coverage for protocol parsing, animation frames, state reduction, hook
  normalization, virtual firmware, and configuration installation.

Physical USB serial transport and RP2040 firmware are planned but not yet
implemented. See the [complete implementation plan](docs/implementation-plan.md)
for the remaining phases.

## Matrix States

| State | Animation |
| --- | --- |
| Booting | Full rows sweep top to bottom through white, blue, cyan, amber, green, and red |
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

## Build and Run

Generate the Xcode project and open the workspace:

```sh
./scripts/generate-xcode-project.sh
open mac/AgentMatrix.xcworkspace
```

Select the `AgentMatrix` scheme and run the app. Agent Matrix appears in the
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

Open **Settings > Integrations** and install the Codex hooks. Agent Matrix:

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
