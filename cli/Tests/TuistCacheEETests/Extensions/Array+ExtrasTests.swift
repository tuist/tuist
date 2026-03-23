import Path
import TuistCore
import TuistSupport
import XcodeGraph
import Testing

@testable import TuistCacheEE
@testable import TuistTesting

struct ArrayExtrasTests {
    actor ActorArray<T> {
        var items: [T] = []
        func insert(_ item: T) {
            items.append(item)
        }
    }

    @Test
    func test_concurrentForEach() async throws {
        // Given
        var randomNumbers: [Int] = []
        for _ in 1 ... 100 {
            let randomNumber = Int.random(in: 1 ... 1000)
            randomNumbers.append(randomNumber)
        }
        let collectedNumbers = ActorArray<Int>()

        // When
        try await randomNumbers.concurrentForEach(maxConcurrentTasks: 5) { item in
            await collectedNumbers.insert(item)
        }

        // Then
        let gotValues = await collectedNumbers.items
        #expect(Set(gotValues) == Set(randomNumbers))
    }
}
