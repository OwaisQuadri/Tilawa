# Tilawa — Coding Standards

## Swift / SwiftUI

- **User preferences**: Use `@AppStorage` in views, not raw `UserDefaults`. For non-view contexts (e.g. `@Observable` classes), use `UserDefaults` with a `Keys` enum (see `MushafViewModel.Keys`).
- **SwiftData queries**: Use `@Query` in views. For imperative fetches, use `modelContext.fetch(FetchDescriptor<...>())`.
- **Observation**: Use `@Observable` (not `ObservableObject`/`@Published`). Pass via `.environment()`, read with `@Environment(MyType.self)`.
- **Naming**: Prefer descriptive names. UserDefaults keys use dot-notation (`"jumpSheet.tab"`, `"mushaf.currentPage"`).
- **Enums backing @AppStorage**: Must be `String`-backed and `CaseIterable` when used with segmented pickers.

## Architecture

- Views live in `Tilawa/Views/`, grouped by feature (e.g. `Mushaf/`, `Library/`).
- ViewModels live in `Tilawa/ViewModels/`.
- Data models live in `Tilawa/Core/Models/` (SwiftData `@Model` classes).
- Quran reference data services live in `Tilawa/Core/QuranData/` (singletons via `.shared`).
- New SwiftData models must be added to the `Schema` array in `TilawaApp.sharedModelContainer`.

## Testing

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Test file naming: `<ClassName>Tests.swift` in `TilawaTests/`.
