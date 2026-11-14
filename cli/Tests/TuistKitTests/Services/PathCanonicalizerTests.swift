import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import TuistKit

struct PathCanonicalizerTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func canonical_resolvesASymlinkedPathItself() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let checkout = temporaryDirectory.appending(component: "checkout")
        try await fileSystem.makeDirectory(at: checkout)
        let link = temporaryDirectory.appending(component: "link")
        try await fileSystem.createSymbolicLink(from: link, to: checkout)
        let subject = PathCanonicalizer()

        let canonicalCheckout = subject.canonical(checkout.pathString)

        #expect(subject.canonical(link.pathString) == canonicalCheckout)
        #expect(subject.canonical(link.pathString + "/Missing/A.swift") == canonicalCheckout + "/Missing/A.swift")
    }

    @Test(.inTemporaryDirectory)
    func canonicalFile_resolvesTheDirectoryAndKeepsTheFileName() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let checkout = temporaryDirectory.appending(component: "checkout")
        try await fileSystem.makeDirectory(at: checkout)
        try await fileSystem.writeText("", at: checkout.appending(component: "A.swift"))
        try await fileSystem.createSymbolicLink(
            from: checkout.appending(component: "Alias.swift"),
            to: checkout.appending(component: "A.swift")
        )
        let link = temporaryDirectory.appending(component: "link")
        try await fileSystem.createSymbolicLink(from: link, to: checkout)
        let subject = PathCanonicalizer()

        let canonicalCheckout = subject.canonical(checkout.pathString)

        #expect(subject.canonicalFile(link.pathString + "/Alias.swift") == canonicalCheckout + "/Alias.swift")
        #expect(subject.canonical(link.pathString + "/Alias.swift") == canonicalCheckout + "/A.swift")
        #expect(subject.canonicalFile("A.swift") == "A.swift")
    }
}
