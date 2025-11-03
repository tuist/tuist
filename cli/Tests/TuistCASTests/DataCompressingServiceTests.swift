import Foundation
import Testing
@testable import TuistCAS

struct DataCompressingServiceTests {
    private let subject = DataCompressingService()

    @Test
    func compress_and_decompress() async throws {
        // Given
        let originalData = Data("Hello, World! This is a test string for compression.".utf8)

        // When
        let compressedData = try await subject.compress(originalData)

        // Then
        #expect(compressedData.count > 0)
        #expect(compressedData != originalData) // Should be different (compressed format)

        let decompressedData = try await subject.decompress(compressedData)
        #expect(decompressedData == originalData)
    }

    @Test
    func compression_reduces_size_for_repetitive_data() async throws {
        // Given
        let repetitiveString = String(repeating: "ABCD", count: 250) // 1000 characters
        let originalData = Data(repetitiveString.utf8)

        // When
        let compressedData = try await subject.compress(originalData)

        // Then
        #expect(compressedData.count < originalData.count)

        // Verify round-trip still works
        let decompressedData = try await subject.decompress(compressedData)
        #expect(decompressedData == originalData)
    }
}
