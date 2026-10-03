import Testing
@testable import TuistKit

struct FormattersTests {
    @Test func formatBytesIsConsistentUnderConcurrentUse() async {
        let values = [2_700_000_000, 1500, 42, 3_456_789, 20_000_000_000]
        let expected = values.map(Formatters.formatBytes)

        let mismatches = await withTaskGroup(of: [String].self) { group in
            for _ in 0 ..< 64 {
                group.addTask {
                    (0 ..< 100).flatMap { _ in
                        zip(values, expected).compactMap { value, expected in
                            let formatted = Formatters.formatBytes(value)
                            return formatted == expected ? nil : "\(expected) -> \(formatted)"
                        }
                    }
                }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }

        #expect(mismatches.isEmpty)
    }
}
