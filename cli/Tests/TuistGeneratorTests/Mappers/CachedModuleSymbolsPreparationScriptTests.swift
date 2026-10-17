import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistGenerator

struct CachedModuleSymbolsPreparationScriptTests {
    @Test(.inTemporaryDirectory)
    func writesModuleScopedMappingsWithoutChangingDebugBytes() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        let original = try Data(contentsOf: resources.appending(components: "DWARF", "Feature").url)
        try execute(at: root)
        let info = try readPlist(resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist"))
        #expect(info["DBGVersion"] as? String == "3")
        #expect(info["DBGSourcePathRemapping"] as? [String: String] == ["/producer/Feature.swift": "/consumer/Feature.swift"])
        #expect(try Data(contentsOf: resources.appending(components: "DWARF", "Feature").url) == original)
    }

    @Test(.inTemporaryDirectory)
    func composesWithTheTargetsCompilerSourceMapInsteadOfRemappingBreakpointsTwice() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        try execute(at: root, prefixMapping: true)
        let info = try readPlist(resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist"))
        #expect(info["DBGSourcePathRemapping"] as? [String: String] == ["/producer/Feature.swift": "/^root/Feature.swift"])
    }

    @Test(.inTemporaryDirectory)
    func preservesExplicitMappingsAndReplacesOnlyItsOwnPreviousEntries() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        let path = resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")
        try writePlist([
            "DBGVersion": "3",
            "DBGSourcePathRemapping": [
                "/producer/Feature.swift": "/explicit/Feature.swift",
                "/producer/Old.swift": "/old/Old.swift",
            ],
            "TuistSourcePathRemapping": ["/producer/Old.swift": "/old/Old.swift"],
        ], at: path)
        try execute(at: root)
        let info = try readPlist(path)
        #expect(info["DBGSourcePathRemapping"] as? [String: String] == ["/producer/Feature.swift": "/explicit/Feature.swift"])
        #expect(info["TuistSourcePathRemapping"] as? [String: String] == [:])
    }

    @Test(.inTemporaryDirectory)
    func doesNotModifySharedMaterializationsOrUnrelatedProducts() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let shared = try await makeDSYM(at: root.appending(component: "cache"), name: "Feature.framework")
        let unrelated = try await makeDSYM(at: root.appending(component: "products"), name: "Unrelated.framework")
        try FileManager.default.createSymbolicLink(
            at: root.appending(components: "products", "Feature.framework.dSYM").url,
            withDestinationURL: shared.parentDirectory.parentDirectory.url
        )
        try execute(at: root)
        #expect(!FileManager.default
            .fileExists(atPath: shared.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist").pathString))
        #expect(!FileManager.default
            .fileExists(atPath: unrelated.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist").pathString))
    }

    @Test(.inTemporaryDirectory)
    func leavesOlderCustomUUIDPlistsUntouched() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        let path = resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")
        try writePlist(["DBGVersion": "2", "DBGSourcePathRemapping": ["/producer": "/explicit"]], at: path)
        let original = try Data(contentsOf: path.url)
        try execute(at: root)
        #expect(try Data(contentsOf: path.url) == original)
    }

    private func makeDSYM(at root: AbsolutePath, name: String) async throws -> AbsolutePath {
        let resources = root.appending(components: name + ".dSYM", "Contents", "Resources")
        try await FileSystem().makeDirectory(at: resources.appending(component: "DWARF"))
        try await FileSystem().writeText("unchanged debug bytes", at: resources.appending(components: "DWARF", "Feature"))
        return resources
    }

    private func execute(at root: AbsolutePath, prefixMapping: Bool = false) throws {
        let script = """
        import json, os, subprocess, sys, types
        environment = {"BUILT_PRODUCTS_DIR": \(pythonString(root.appending(component: "products").pathString))}
        mappings = \(prefixMapping ? "{'/^root': '/consumer'}" : "{}")
        compiler_precedence = lambda mapping: -len(mapping[1])
        plan = {"mappings": [["/producer/Feature.swift", "/consumer/Feature.swift"]], "artifacts": [],
                "nativeProducts": ["Feature.framework"], "requiresLinkedDebugInformation": False}
        def run(arguments, **kwargs):
            assert arguments[:2] == ["/usr/bin/xcrun", "dwarfdump"]
            assert len(arguments) == 4
            output = "/producer/Feature.swift\\n" if arguments[2] == "--show-sources" else "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64)\\n"
            return types.SimpleNamespace(stdout=output)
        subprocess.run = run
        \(CachedModuleSymbolsPreparationScript.value)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: data, as: UTF8.self)))
    }

    private func pythonString(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
    }

    private func writePlist(_ info: [String: Any], at path: AbsolutePath) throws {
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: path.url)
    }

    private func readPlist(_ path: AbsolutePath) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: path.url), format: nil) as? [String: Any])
    }
}
