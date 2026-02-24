# AGENTS.md

Guidelines for AI agents working on the Cousebara codebase.

## Project Overview

Cousebara is a macOS 14+ menu bar app that monitors GitHub Copilot premium interaction usage. It uses The Composable Architecture (TCA) for state management and SwiftUI for the UI. No App Sandbox (reads `~/.config/github-copilot/apps.json`). Distributed via Homebrew Cask, not the Mac App Store.

## Build & Test Commands

**Prefer the Xcode MCP tools** (`xcode_BuildProject`, `xcode_RunAllTests`, `xcode_RunSomeTests`, etc.) over `xcodebuild` CLI commands when available. MCP tools integrate directly with the open Xcode workspace and handle configuration automatically. Fall back to the CLI commands below when MCP is not available or for CI.

### Build

Xcode MCP: `xcode_BuildProject`

```sh
xcodebuild -project Cousebara.xcodeproj -scheme Cousebara -configuration Debug build
```

### Run All Tests

Xcode MCP: `xcode_RunAllTests`

```sh
xcodebuild test \
  -project Cousebara.xcodeproj \
  -scheme Cousebara \
  -destination 'platform=macOS' \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

### Run a Single Test

Xcode MCP: `xcode_RunSomeTests` with `targetName: "CousebaraTests"` and `testIdentifier: "<TestStruct>/<testFunctionName>"`.

```sh
xcodebuild test \
  -project Cousebara.xcodeproj \
  -scheme Cousebara \
  -destination 'platform=macOS' \
  -only-testing:'CousebaraTests/PopoverFeatureTests/onAppLaunch_fetchesUsageAndStartsTimer' \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

Format: `-only-testing:'CousebaraTests/<TestStruct>/<testFunctionName>'`

### Run a Single Test Class

Xcode MCP: `xcode_RunSomeTests` with `targetName: "CousebaraTests"` and `testIdentifier: "<TestStruct>"`.

```sh
xcodebuild test \
  -project Cousebara.xcodeproj \
  -scheme Cousebara \
  -destination 'platform=macOS' \
  -only-testing:'CousebaraTests/PopoverFeatureTests' \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

Test targets: `CousebaraTests` (test files: `AuthFeatureTests.swift`, `PopoverFeatureTests.swift`).

## Architecture

Uses The Composable Architecture (TCA) with filesystem-synced Xcode project (objectVersion 77 -- files added to `Cousebara/` are automatically included in the build).

| Directory | Purpose |
|---|---|
| `Cousebara/App/` | App entry point (`CousebaraApp.swift`) and root reducer (`AppFeature.swift`) |
| `Cousebara/Features/` | TCA feature modules: `Auth/` (sign-in flow), `Popover/` (main UI) |
| `Cousebara/Dependencies/` | `@DependencyClient` types: `CopilotAPIClient`, `GitHubAuthClient`, `AppTerminator` |
| `Cousebara/Models/` | Decodable response models, error enums, mock data |
| `Cousebara/Views/` | Shared views: `ContentView`, `MenuBarLabel` |
| `CousebaraTests/` | Swift Testing tests using TCA `TestStore` |

### TCA Conventions

- Feature structs are annotated with `@Reducer` and contain nested `State` and `Action` types.
- State structs use `@ObservableState`. Child presentation state uses `@Presents`.
- Dependency injection via `@Dependency(\.someClient)` in reducer bodies.
- Dependency clients are structs with `@DependencyClient`, conforming to `Sendable`, `TestDependencyKey`, and `DependencyKey`.
- Effects return `Effect<Action>`. Async work uses `.run { send in ... }` with `Result`-wrapped responses.
- Timer effects use `clock.timer(interval:)` with `.cancellable(id:)`.
- Child features composed with `.ifLet(\.$child, action: \.child)` or `Scope(state:action:)`.

## Code Style

### Imports

- One import per line, sorted alphabetically.
- `@testable import` after regular imports, separated by a blank line.

### Naming

- **Types**: `UpperCamelCase`. Suffixes: `*Feature` (reducers), `*View` (SwiftUI views), `*Client` (dependencies), `*Response` (API models), `*Error` (error enums), `*Tests` (test suites).
- **Properties/functions**: `lowerCamelCase`. Boolean properties use `is` prefix (`isOverLimit`, `isLoading`).
- **TCA actions**: User actions use past tense with `Tapped` suffix (`quitButtonTapped`, `refreshButtonTapped`). Effect results use noun phrases with `Result` (`usageResponse(Result<...>)`). Lifecycle events: `onAppLaunch`, `timerTicked`.
- **Test functions**: `camelCase` with underscores separating scenario from expectation: `fetchUsage_tokenFileMissing_showsAuthFlow`.

### Formatting

- 4-space indentation (no tabs).
- K&R brace style (opening brace on same line).
- No strict line length limit; lines generally stay under ~110 chars. Break long lines at parameters, aligning to the opening delimiter.
- Trailing commas in multi-line collections and parameter lists.
- One blank line between top-level declarations and before `// MARK: -` comments.

### Access Control

- Default to `internal` (implicit). Use `private` for implementation details (computed properties, helper methods, constants) within views and reducers. Never use `public`, `open`, or `fileprivate`.

### Swift Language Features

- Prefer `guard let` for early exits and error returns. Use `if let` for conditional rendering in SwiftUI.
- Use implicit returns in single-expression closures, computed properties, and switch cases.
- Use `if`/`else` as expressions where they simplify code.
- Use `#Preview("Label")` macro (not `PreviewProvider`) with descriptive labels for multiple states.
- Use `@Shared(.appStorage(...))` for persistent user preferences.

### Error Handling

- Custom error enums conforming to `LocalizedError, Equatable` with `errorDescription` computed property.
- All model types and errors conform to `Sendable`.
- Async effects wrap calls in `Result { ... }` and send result actions.
- `do/catch` used sparingly, only for synchronous error recovery within reducers.
- No force unwraps in production code except for known-valid URL string literals.

### Comments and Documentation

- `// MARK: - SectionName` for file organization (always with dash).
- `///` doc comments for non-obvious computed properties and types.
- Sparse inline `//` comments only for complex logic.
- No `// TODO:` or `// FIXME:` in committed code.

### Protocol Conformances

- One extension per protocol conformance for dependency clients: main struct, then `extension: TestDependencyKey`, then `extension: DependencyKey`.
- Conformance ordering: `Decodable, Equatable, Sendable` (alphabetical/semantic).

### Testing

- Uses Swift Testing framework (`@Test`, `#expect`), not XCTest.
- Test structs annotated with `@MainActor`.
- Tests use TCA `TestStore` with overridden dependencies.
- Test display names via `@Test func descriptiveName() async { ... }`.
- Local error types defined in test files for specific failure scenarios.
- Exhaustive action assertion: tests receive and verify every action the store processes.

### Dependencies

- Managed via Swift Package Manager (Xcode-integrated, no standalone `Package.swift`).
- Single direct dependency: `swift-composable-architecture` (v1.24.1+).
- `@DependencyClient` closures are all `@Sendable`.
- Live implementations in `extension Client: DependencyKey { static var liveValue }`.
- Preview values in `extension Client: TestDependencyKey { static var previewValue }`.

### SwiftUI Patterns

- Views receive `StoreOf<Feature>` (use `@Bindable` when two-way bindings are needed).
- View body decomposed into `private var` (no parameters) and `private func` (with parameters).
- Store scoping via `store.scope(state: \.child, action: \.child)` with key-path syntax.
- Numeric literal underscores for readability (`1_000_000`).

## CI

GitHub Actions runs on `macos-15` for PRs to `main`. The workflow builds and runs all tests with code signing disabled. See `.github/workflows/tests.yml`.
