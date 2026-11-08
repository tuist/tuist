import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistHasher

struct SwiftPackageHeadersHashTests {
    @Test(.inTemporaryDirectory) func privateTemplateAndModuleMapEditsInvalidateHash() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let header = root.appending(component: "Private.ipp")
        let moduleMap = root.appending(component: "module.modulemap")
        try await fileSystem.writeText("original", at: header)
        try await fileSystem.writeText("module CLib {}", at: moduleMap)
        let headers = Headers(public: [], private: [], project: [header], sourceLayout: .init(
            root: root, publicHeaders: root, moduleMap: moduleMap,
            moduleName: "CLib", usesDirectoryModuleMap: false
        ))
        func hash() async throws -> String {
            try await HeadersContentHasher(contentHasher: ContentHasher()).hash(headers: headers)
        }
        let original = try await hash()
        try await fileSystem.writeText("changed", at: header, encoding: .utf8, options: [.overwrite])
        let changedHeader = try await hash()
        #expect(original != changedHeader)
        try await fileSystem.writeText("module CLib { export * }", at: moduleMap, encoding: .utf8, options: [.overwrite])
        #expect(try await hash() != changedHeader)
    }

    @Test(.inTemporaryDirectory) func hashIsPortableButIncludesRelativeHeaderPaths() async throws {
        let temporary = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        func hash(checkout: String, name: String) async throws -> String {
            let root = temporary.appending(component: checkout)
            try await fileSystem.makeDirectory(at: root)
            let header = root.appending(component: name)
            let moduleMap = root.appending(component: "module.modulemap")
            try await fileSystem.writeText("int value(void);", at: header, encoding: .utf8, options: [.overwrite])
            try await fileSystem.writeText(
                "module CLib { umbrella \"\(root.pathString)\" export * }", at: moduleMap,
                encoding: .utf8, options: [.overwrite]
            )
            return try await HeadersContentHasher(contentHasher: ContentHasher()).hash(headers: .init(
                public: [header], private: [], project: [], sourceLayout: .init(
                    root: root, publicHeaders: root, moduleMap: moduleMap, moduleName: "CLib", usesDirectoryModuleMap: true
                )
            ))
        }
        let original = try await hash(checkout: "first", name: "Original.h")
        #expect(try await hash(checkout: "second", name: "Original.h") == original)
        #expect(try await hash(checkout: "second", name: "Renamed.h") != original)
    }
}
