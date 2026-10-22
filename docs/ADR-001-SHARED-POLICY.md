# ADR-001: Compile one native policy component for Swift and .NET

Status: Accepted for implementation. Date: 2026-10-22.

## Context

The native clients use Swift/AppKit/SwiftUI and C#/WPF. Sharing UI would require
a runtime migration and sacrifice their platform integration. Repeating the
learning and news decisions in both languages would allow their behavior to drift.
Reading must also work on Macs using only the system engines, without Python.

## Decision

`Shared/BabelPolicy` is a small C11 library with a versioned C ABI. It owns anchor
selection, challenge budgets, evidence classification, networking/digest gates,
news scoring, matching, duplicate-title rules, and the approved feed list.
SwiftPM compiles the same sources statically; .NET calls the Windows DLL through
a portable P/Invoke adapter. No network, storage, UI or model code lives in it.

OS networking and XML parsing, cancellation, persistence and controls remain
thin native adapters. `Sources/BabelNews` and the Windows news service both use
the shared decisions. They do not send learning inputs to DR.

## Alternatives

- Duplicated Swift/C# policy with fixtures: easier initial builds, but rule changes
  still require two implementations. Shared fixtures alone do not remove that work.
- Python worker: already suitable for installed models, but unsuitable as a mandatory
  dependency for every lookup or for framework-only Mac installations.
- Shared web UI/runtime: much larger migration, unrelated to policy correctness.

## Consequences and validation

Windows source builds additionally require CMake and the Visual Studio C++ tools.
Published apps include the native DLL and require neither build tool on user machines.
Mac already requires the Xcode C compiler; there is no extra runtime dependency.
Keep the ABI primitive and stateless and increment its version for incompatible changes.
Use the common `Tests/Shared/policy-runtime.json` against the real compiled component
from both native test programs. News tests use fictional RSS and fake transports.
