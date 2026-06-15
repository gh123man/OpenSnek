# Getting Started With New Device Support

This guide is for contributors who have an unsupported Razer mouse and want to help OpenSnek support it. It does not replace the protocol docs or contributor guide; it helps you pick a path and gather the right evidence before opening an issue or pull request.

Start with the device you have in front of you. New support usually begins with a precise model name, USB/Bluetooth IDs, and a small set of focused probes or captures that prove which existing protocol paths the device already matches.

## Before You Start

Read these first:

- [CONTRIBUTING.md](../../CONTRIBUTING.md): canonical contribution workflow and code areas
- [docs/DEVICE_SUPPORT.md](../DEVICE_SUPPORT.md): current support matrix and status labels
- [docs/protocol/PROTOCOL.md](../protocol/PROTOCOL.md): protocol index
- [docs/development/VALIDATION.md](./VALIDATION.md): build, test, probe, and hardware validation commands
- [captures/README.md](../../captures/README.md): how to organize protocol captures

If you are changing protocol behavior, update protocol docs, tests, and [CHANGELOG.md](../../CHANGELOG.md) in the same change. If you are only reporting a device or gathering evidence, you do not need to edit code yet.

## What To Gather

OpenSnek needs device support to be transport-specific. A mouse can be supported over USB, Bluetooth, or both, and each transport may expose different features.

Gather as much of this as you can:

- Exact marketing name, model number, and firmware version if available.
- USB vendor ID and product ID.
- Bluetooth name and Bluetooth vendor/product IDs if the mouse supports BLE.
- Which transport you want to support first: USB, Bluetooth, or both.
- Which features matter most: DPI stages, active DPI stage, lighting, button remap, battery, sleep timeout, poll rate, scroll controls.
- Probe output or captures from default state and from one changed setting at a time.
- Whether validation is from your hardware. Contributor hardware results should be described as `Contributor validated`, not `Validated`.

## Path 1: Human-Only Workflow

Use this path if you want to work through the repo manually without an LLM or coding agent.

### 1. Build The Probe

From the repo root:

```bash
swift build --package-path OpenSnek --product OpenSnekProbe
```

If that fails, check [OpenSnek/README.md](../../OpenSnek/README.md) and [docs/development/VALIDATION.md](./VALIDATION.md) for local build notes.

### 2. Identify The Device

For USB devices, start with the macOS System Information app, `ioreg`, or HID tooling to find the Razer vendor ID and product ID. For Bluetooth devices, record the advertised name exactly as macOS sees it.

Then compare against:

- [docs/DEVICE_SUPPORT.md](../DEVICE_SUPPORT.md)
- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift`
- [docs/protocol/PARITY.md](../protocol/PARITY.md) when support status or transport parity changes

### 3. Try Existing Probe Commands

USB examples:

```bash
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-info --pid 0x00ab
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-read --zone all --pid 0x00ab
```

Bluetooth examples:

```bash
swift run --package-path OpenSnek OpenSnekProbe dpi-read
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-info --name "YOUR MOUSE NAME"
```

Use the closest existing command first. Many Razer mice share enough protocol shape that a new profile can often reuse existing USB or Bluetooth paths.

### 4. Capture One Change At A Time

If an existing probe command does not work, capture the official app or known-good control path changing exactly one setting at a time.

Good capture sets include:

- default state read
- one DPI stage change
- active DPI stage change
- one lighting color or brightness change
- one button remap
- readback or refresh after each write

For Bluetooth reverse engineering, start with [docs/research/BLE_REVERSE_ENGINEERING.md](../research/BLE_REVERSE_ENGINEERING.md). For capture organization, use [captures/README.md](../../captures/README.md).

### 5. Make The Smallest Code Change

Most new devices start in `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift`:

- add a `DeviceProfileID`
- register USB and/or Bluetooth identities
- define button layout and writable slots
- set capability flags honestly
- expose only features you have proven

If new bytes need to be decoded, keep shared parsing/building code in:

- `OpenSnek/Sources/OpenSnekProtocols/USBHIDProtocol.swift`
- `OpenSnek/Sources/OpenSnekProtocols/BLEVendorProtocol.swift`
- shared transport/session code under `OpenSnek/Sources/OpenSnekHardware`

Avoid special-casing raw product IDs in SwiftUI. Device-specific behavior should usually live in profiles, protocol helpers, or bridge code.

### 6. Add Tests And Docs

At minimum, add profile tests for new identities and capabilities:

```bash
swift test --package-path OpenSnek --filter DeviceProfilesTests
```

For protocol changes, add focused parser/builder tests and run the matching protocol suite:

```bash
swift test --package-path OpenSnek --filter USBHIDProtocolTests
swift test --package-path OpenSnek --filter BLEVendorProtocolTests
```

Before saying the work is done or opening a final PR, run the complete suite:

```bash
swift test --package-path OpenSnek
```

Update these docs when applicable:

- [docs/DEVICE_SUPPORT.md](../DEVICE_SUPPORT.md)
- [docs/protocol/PROTOCOL.md](../protocol/PROTOCOL.md)
- [docs/protocol/USB_PROTOCOL.md](../protocol/USB_PROTOCOL.md)
- [docs/protocol/BLE_PROTOCOL.md](../protocol/BLE_PROTOCOL.md)
- [docs/protocol/PARITY.md](../protocol/PARITY.md)
- [CHANGELOG.md](../../CHANGELOG.md)

## Path 2: LLM-Guided Workflow

This repository is optimized for coding-agent workflows. A capable agent can often inspect the existing support matrix, route itself through the right files, add a profile, write tests, and ask you to run hardware probes when it needs data from your mouse.

Use this path if you have Codex, Claude Code, or another coding agent with local repository access.

### 1. Give The Agent Concrete Context

Clone the repo, open it in your agent, connect the mouse, and start with a prompt like:

```text
Add OpenSnek support for the Razer <exact model name>.

I have the hardware connected over <USB/Bluetooth/both>.
The model number is <model>.
The USB product ID is <0x....> if known.
The Bluetooth name is "<name>" if known.

Please inspect the existing OpenSnek device-support docs and code, add the smallest safe support change, and walk me through any probe commands you need me to run.
Do not mark the device as Validated unless the repo rules allow it; use Contributor validated for my hardware results.
```

If you are starting from an issue with little data, ask the agent to gather requirements first:

```text
Help me collect the information needed to add this unsupported Razer mouse to OpenSnek.
Start from the new-device support guide and ask me for the next probe or capture output one step at a time.
```

### 2. Let The Agent Use The Repo Routing

The repo includes `AGENTS.md` instructions for common task areas. A good agent should read those instructions and then open the relevant files, especially:

- `CONTRIBUTING.md`
- `docs/development/VALIDATION.md`
- `docs/protocol/PROTOCOL.md`
- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift`
- protocol and bridge files for the transport being changed

You should expect the agent to prefer focused tests and focused probe commands while developing, then run the full test suite before publishing.

### 3. Run Hardware Commands Locally

The agent cannot invent hardware validation. When it asks you to run a command, run it with your mouse connected and paste back the full output.

Common examples:

```bash
swift build --package-path OpenSnek --product OpenSnekProbe
swift run --package-path OpenSnek OpenSnekProbe dpi-read
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-info --name "YOUR MOUSE NAME"
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-info --pid 0x00ab
```

If a Bluetooth probe crashes with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`, fix macOS Bluetooth permission for the launching terminal or app before debugging protocol logic. See [docs/development/VALIDATION.md](./VALIDATION.md#permissions--tcc).

### 4. Review What The Agent Changes

Before opening a pull request, check that the agent did not overclaim support:

- status labels match the evidence
- unsupported or untested features stay hidden
- protocol behavior changes include tests and docs
- `CHANGELOG.md` is updated for user-visible or protocol-visible changes
- the full unit test suite passes locally

Ask the agent to summarize hardware validation as `pass`, `fail`, or `skipped`, including which commands produced that result.

## Opening A Good Issue Or PR

For an issue, include:

- exact device name and model number
- transport requested: USB, Bluetooth, or both
- USB product ID and Bluetooth name/ID if known
- which features you tested
- probe output or capture links
- whether you can run additional commands

For a pull request, include:

- what device and transport were added
- what features are shipped, mapped, or contributor-validated
- capture/probe evidence used
- tests run, including `swift test --package-path OpenSnek`
- any known gaps or intentionally hidden controls

Small, evidence-backed support is better than a broad profile that exposes untested controls.
