# Agent Matrix Contributor Guide

## Scope

Agent Matrix is a privacy-minimal macOS menu-bar utility that maps coding-agent
lifecycle events to a simulated or physical 5x5 RGB matrix. The simulator and
physical device must consume the same semantic states and protocol contracts.

The repository implements the software vertical slice, automatic USB serial
routing with simulator fallback, protocol-gated connected-device testing, and
bundled RP2040 firmware installation from the simulator. The original phase plan
is retained in `docs/implementation-plan.md` for architecture context.

## Project Generation

- `project.yml` is the source of truth for Xcode targets, dependencies, build
  settings, schemes, and navigator file groups.
- Never hand-edit `AgentMatrix.xcodeproj/project.pbxproj`.
- After adding, moving, or removing files, run
  `./scripts/generate-xcode-project.sh` and commit the regenerated project.
- Open `mac/AgentMatrix.xcworkspace`, not the generated project directly.
- Ensure every created repository file is visible through a source group or a
  root `fileGroups` entry in `project.yml`.

## Module Boundaries

- `AgentMatrixProtocol`: Codable event models, display states, matrix frames,
  wire commands/responses, transport contracts, and generated animations. It
  must not import app or simulator modules.
- `AgentMatrixCore`: session reduction, aggregate state, matrix coordination,
  local IPC, hook normalization, and Codex configuration installation.
- `AgentMatrixSimulator`: deterministic matrix rendering, virtual firmware,
  runtime transport routing, and connected-device tools. Protocol behavior
  belongs in `VirtualFirmware`, not in SwiftUI animation callbacks.
- `AgentMatrixApp`: scene composition, menu-bar UI, onboarding, settings, and
  app lifecycle wiring. Keep business logic in Core or Simulator.
- `AgentMatrixHook`: standalone executable. It must not dynamically depend on
  project frameworks because it is copied outside the app bundle.
- `AgentMatrixTests`: focused unit coverage for contracts and state behavior.
- `firmware`: RP2040 AM1 implementation and WS2812 rendering. Keep its semantic
  states aligned with `shared/animations.json` and `GeneratedAnimations.swift`.

Do not introduce dependencies from lower-level modules back into the app.

## UI and Previews

- Use native SwiftUI and AppKit conventions for this compact macOS utility.
- Every type conforming to `View` must have a useful Xcode `#Preview` in the same
  file. Preview data must not write hooks, start IPC servers, or mutate user
  configuration.
- Keep the menu-bar popover compact. Put protocol diagnostics and fault controls
  in the simulator or Developer settings.
- Use SF Symbols for commands and status where a suitable symbol exists.
- Matrix states must remain distinguishable through pattern or motion, not only
  color.
- Respect stable control dimensions and avoid nested cards or decorative UI.

## Animation Contract

- `shared/animations.json` is the cross-platform animation specification.
- Until the asset generator is implemented, update
  `GeneratedAnimations.swift` in the same change and keep both representations
  identical.
- Animations use explicit 25-pixel frames and deterministic durations. Do not
  use implicit SwiftUI animation as protocol or firmware state.
- Preserve the firmware brightness ceiling of `64 / 255`; avoid sustained
  full-matrix white frames.
- Add or update frame assertions in `ProtocolTests.swift` for animation changes.
- Rebuild `firmware/artifacts/DeskAgent.uf2` with
  `./scripts/build-firmware.sh` whenever firmware source changes.

## Privacy and Hook Safety

- Never forward or log prompts, assistant messages, source code, transcripts,
  environment variables, tool input, or tool output.
- The helper must accept bounded input, send one compact datagram, never block
  waiting for the app, and exit successfully when the app is unavailable.
- Standard output must remain empty except for required hook contracts such as
  the `Stop` response `{}`.
- Keep the Unix socket user-owned and mode `0600`; reject foreign-owned paths.
- Parse and structurally merge `~/.codex/hooks.json`. Never string-edit it,
  overwrite malformed JSON, remove unrelated hooks, or bypass Codex trust.
- Tests for installers must use temporary home directories. Never mutate the
  developer's real Codex configuration from a test or preview.

## Validation

Run project generation whenever project structure changes:

```sh
./scripts/generate-xcode-project.sh
```

Run the macOS build and unit suite before committing:

```sh
./scripts/build-mac.sh
```

Validate firmware changes with:

```sh
./scripts/build-firmware.sh
```

For unsigned local validation, use:

```sh
xcodebuild \
  -workspace mac/AgentMatrix.xcworkspace \
  -scheme AgentMatrix \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Also run `git diff --check`. For hook changes, verify the built helper with
`otool -L` and exercise `UserPromptSubmit`, `PermissionRequest`, and `Stop`
against the running app.

## Change Discipline

- Keep changes scoped to the requested behavior and preserve the shared protocol
  contract across simulator and hardware paths.
- Preserve current user work in a dirty worktree and stage explicit paths.
- Update README or docs when behavior, setup, protocol, or phase status changes.
- Do not commit build output, DerivedData, user Xcode state, local logs, or hook
  configuration backups.
