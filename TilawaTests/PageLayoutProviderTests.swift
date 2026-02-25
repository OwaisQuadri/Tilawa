import Testing
@testable import Tilawa

struct PageLayoutProviderTests {

    @Test func loadPageOne() async throws {
        let provider = PageLayoutProvider()
        let layout = try await provider.layout(for: 1)
        #expect(layout.page == 1)
        #expect(layout.lines.count > 0)
    }

    @Test func cacheHit() async throws {
        let provider = PageLayoutProvider()
        _ = try await provider.layout(for: 1)
        let count = await provider.cacheCount
        #expect(count == 1)

        // Second load should use cache
        _ = try await provider.layout(for: 1)
        let count2 = await provider.cacheCount
        #expect(count2 == 1)
    }

    @Test func eviction() async throws {
        let provider = PageLayoutProvider()
        _ = try await provider.layout(for: 1)
        _ = try await provider.layout(for: 100)
        _ = try await provider.layout(for: 200)

        let countBefore = await provider.cacheCount
        #expect(countBefore == 3)

        // Evict outside range 95-105
        await provider.evict(outside: 95...105)
        let countAfter = await provider.cacheCount
        #expect(countAfter == 1) // Only page 100 remains
    }

    @Test func loadLastPage() async throws {
        let provider = PageLayoutProvider()
        let layout = try await provider.layout(for: 604)
        #expect(layout.page == 604)
        #expect(layout.lines.count > 0)
    }

    @Test func invalidPageThrows() async {
        let provider = PageLayoutProvider()
        do {
            _ = try await provider.layout(for: 0)
            #expect(Bool(false), "Expected error for page 0")
        } catch {
            // Expected
        }
    }
}
