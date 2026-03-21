---
name: test
description: Use this skill when the user wants to run the full OpenSnek unit test suite or verify all Swift package tests locally. It runs the same `swift test --package-path OpenSnek` command used by CI and the release script, without enabling hardware-gated tests unless the user asks for them.
---

# Test

## Overview

Use this skill to run the full OpenSnek Swift package unit test suite from the repository root.

The default command is `swift test --package-path OpenSnek`.

## Workflow

1. Start from the repository root and run `swift test --package-path OpenSnek`.
2. Treat that command as the canonical full unit-test pass for this repo; it matches the release preflight and CI test step.
3. Keep hardware-gated suites separate unless the user explicitly asks for them, for example `OPEN_SNEK_HW=1 swift test --package-path OpenSnek --filter HardwareDpiReliabilityTests`.
4. If tests fail, report the failing test targets or cases and point to the most relevant files or commands for follow-up.

## Guardrails

- Do not substitute focused filters when the user asked for all unit tests.
- Do not enable `OPEN_SNEK_HW=1` or other hardware gates by default.
- If the environment blocks the test run, report the exact command and failure mode instead of guessing.
