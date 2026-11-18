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
    func listsSourcesAgainOnlyWhenTheDebugInformationOrRelocationsChange() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        let path = resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")
        #expect(try execute(at: root) == 1)
        #expect(try execute(at: root) == 0)
        try await FileSystem().remove(path)
        #expect(try execute(at: root) == 0)
        #expect(try readPlist(path)["DBGSourcePathRemapping"] as? [String: String] == [
            "/producer/Feature.swift": "/consumer/Feature.swift",
        ])

        #expect(try execute(at: root, observedSource: "/producer/Other.swift", producer: "/producer/Other.swift") == 1)
        #expect(try readPlist(path)["DBGSourcePathRemapping"] as? [String: String] == [
            "/producer/Other.swift": "/consumer/Feature.swift",
        ])

        let dwarf = resources.appending(components: "DWARF", "Feature")
        try await FileSystem().remove(dwarf)
        try await FileSystem().writeText("relinked debug bytes", at: dwarf)
        #expect(try execute(at: root, observedSource: "/consumer/OnlyNative.swift", producer: "/producer/Other.swift") == 1)
        #expect(try readPlist(path)["DBGSourcePathRemapping"] as? [String: String] == [:])
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
    func skipsSourcesTheCompilerSourceMapAlreadyResolves() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        #expect(try execute(
            at: root, prefixMapping: true, observedSource: "/^root/Feature.swift", producer: "/^root/Feature.swift"
        ) == 0)
        #expect(!FileManager.default
            .fileExists(atPath: resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist").pathString))
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

    @Test(.inTemporaryDirectory, arguments: ["malformed", "symlink"])
    func preservesUnreadableAndSymlinkedUUIDPlists(kind: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        let path = resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")
        let original = Data("custom invalid plist".utf8)
        if kind == "symlink" {
            let outside = root.appending(component: "custom.plist")
            try original.write(to: outside.url)
            try FileManager.default.createSymbolicLink(at: path.url, withDestinationURL: outside.url)
        } else {
            try original.write(to: path.url)
        }
        try execute(at: root)
        #expect(try Data(contentsOf: path.url) == original)
    }

    @Test(.inTemporaryDirectory, arguments: [
        "new", "owned-stale", "custom-stale", "owned-custom", "uuid-mismatch", "tool-failure", "shared", "shared-image",
    ])
    func staticCompanionsRespectOwnershipUUIDsAndImmutableImages(mode: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let products = root.appending(component: "products")
        try await FileSystem().makeDirectory(at: products)
        let binary = products.appending(component: "Consumer")
        try await FileSystem().writeText("immutable executed image", at: binary)
        let before = try Data(contentsOf: binary.url)
        let dsym = products.appending(component: "Consumer.dSYM")
        let dynamic = try await makeDSYM(at: products, name: "Feature.framework")
        if ["owned-stale", "custom-stale", "owned-custom"].contains(mode) {
            let resources = try await makeDSYM(at: products, name: "Consumer")
            if mode != "custom-stale" {
                try JSONSerialization.data(withJSONObject: ["version": 1, "uuids": ["BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE"]])
                    .write(to: resources.appending(component: "tuist-debug-companion.json").url)
            }
            if mode == "owned-custom" {
                try writePlist([
                    "DBGVersion": "3", "DBGSourcePathRemapping": ["/producer/Feature.swift": "/user/Feature.swift"],
                ], at: resources.appending(component: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist"))
            }
        }
        if mode == "shared-image" {
            let image = root.appending(components: "cache", "Consumer")
            try await FileSystem().makeDirectory(at: image.parentDirectory)
            try await FileSystem().writeText("immutable executed image", at: image)
            try await FileSystem().remove(binary)
            try FileManager.default.createSymbolicLink(at: binary.url, withDestinationURL: image.url)
        }
        if mode == "shared" {
            let resources = try await makeDSYM(at: root.appending(component: "cache"), name: "Consumer")
            try FileManager.default.createSymbolicLink(
                at: dsym.url,
                withDestinationURL: resources.parentDirectory.parentDirectory.url
            )
        }
        let script = """
        import json, os, pathlib, subprocess, sys, types
        environment = {"TARGET_BUILD_DIR": \(pythonString(products.pathString)), "EXECUTABLE_PATH": "Consumer",
                       "FULL_PRODUCT_NAME": "Consumer", "COMPILATION_CACHE_ENABLE_CACHING": "YES",
                       "TARGET_TEMP_DIR": \(pythonString(root.pathString))}
        mappings = {}
        compiler_precedence = lambda mapping: -len(mapping[1])
        plan = {"mappings": [["/producer/Feature.swift", "/consumer/Feature.swift"]], "artifacts": [\(pythonString(root
                .appending(component: "cache").pathString))],
                "nativeProducts": ["Feature.framework"], "requiresLinkedDebugInformation": True}
        mode = \(pythonString(mode))
        calls = []
        state = {"fresh": False}
        def run(arguments, **kwargs):
            calls.append(arguments)
            if arguments[:2] == ["/usr/bin/xcrun", "--find"]:
                return types.SimpleNamespace(stdout="/toolchain/" + arguments[2] + "\\n")
            if arguments[0] == "/toolchain/dsymutil":
                if mode == "tool-failure":
                    raise subprocess.CalledProcessError(1, arguments)
                assert ["-cas", "/local/cas"] == arguments[1:3]
                assert "-cas-plugin-option" in arguments
                staged = pathlib.Path(arguments[-1]) / "Contents/Resources/DWARF"
                staged.mkdir(parents=True)
                (staged / "Consumer").write_text("linked debug information")
                state["fresh"] = True
                return types.SimpleNamespace(stdout="")
            assert arguments[0] == "/toolchain/dwarfdump"
            if arguments[1] == "--show-sources":
                return types.SimpleNamespace(stdout="/producer/Feature.swift\\n")
            path = arguments[-1]
            stale = mode in ("owned-stale", "custom-stale", "owned-custom") and not state["fresh"] and ".tuist-debug-symbols-" not in path and path.endswith("/Consumer.dSYM")
            mismatch = mode == "uuid-mismatch" and ".tuist-debug-symbols-" in path
            uuid = "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE" if stale or mismatch else "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            return types.SimpleNamespace(stdout="UUID: " + uuid + " (arm64)\\n")
        subprocess.run = run
        error = None
        try:
            exec(\(String(reflecting: CachedModuleSymbolsPreparationScript.value)))
        except Exception as failure:
            error = str(failure)
        print(json.dumps({"error": error, "linked": any(call[0] == "/toolchain/dsymutil" for call in calls)}))
        """
        try JSONSerialization.data(withJSONObject: [
            "CASPath": "/local/cas", "PluginPath": "/local/plugin.dylib", "PluginOptions": [["remote-service-path": "/socket"]],
        ]).write(to: root.appending(component: ".cas-config").url)
        let result = try runPython(script)
        #expect(try Data(contentsOf: binary.url) == before)
        #expect((result["error"] as? String != nil) == ["custom-stale", "owned-custom", "uuid-mismatch", "tool-failure"]
            .contains(mode))
        #expect(result["linked"] as? Bool == !["custom-stale", "owned-custom", "shared", "shared-image"].contains(mode))
        let dynamicMap = dynamic.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")
        #expect(try readPlist(dynamicMap)["TuistSourcePathRemapping"] as? [String: String] == [
            "/producer/Feature.swift": "/consumer/Feature.swift",
        ])
        if mode == "new" || mode == "owned-stale" {
            #expect(FileManager.default.fileExists(atPath: dsym.appending(
                components: "Contents",
                "Resources",
                "tuist-debug-companion.json"
            ).pathString))
        } else if mode != "owned-custom" {
            #expect(!FileManager.default.fileExists(atPath: dsym.appending(
                components: "Contents",
                "Resources",
                "tuist-debug-companion.json"
            ).pathString))
        }
        if mode == "owned-custom" {
            let custom = dsym.appending(components: "Contents", "Resources", "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")
            #expect(try readPlist(custom)["DBGSourcePathRemapping"] as? [String: String] == [
                "/producer/Feature.swift": "/user/Feature.swift",
            ])
        }
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func avoidsEmptyMapsForUnrelatedSymbolsButClearsStaleOwnedMappings(existing: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let resources = try await makeDSYM(at: root.appending(component: "products"), name: "Feature.framework")
        let path = resources.appending(component: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist")
        if existing {
            let previous = ["/producer/Previous.swift": "/consumer/Previous.swift"]
            try writePlist(
                ["DBGVersion": "3", "DBGSourcePathRemapping": previous, "TuistSourcePathRemapping": previous],
                at: path
            )
        }
        try execute(at: root, observedSource: "/consumer/OnlyNative.swift")
        #expect(FileManager.default.fileExists(atPath: path.pathString) == existing)
        if existing {
            #expect(try readPlist(path)["DBGSourcePathRemapping"] as? [String: String] == [:])
        }
    }

    private func runPython(_ script: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: diagnostics, as: UTF8.self)))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeDSYM(at root: AbsolutePath, name: String) async throws -> AbsolutePath {
        let resources = root.appending(components: name + ".dSYM", "Contents", "Resources")
        try await FileSystem().makeDirectory(at: resources.appending(component: "DWARF"))
        try await FileSystem().writeText("unchanged debug bytes", at: resources.appending(components: "DWARF", "Feature"))
        return resources
    }

    /// Returns how many times the script listed a dSYM's sources.
    @discardableResult
    private func execute(
        at root: AbsolutePath,
        prefixMapping: Bool = false,
        observedSource: String = "/producer/Feature.swift",
        producer: String = "/producer/Feature.swift"
    ) throws -> Int {
        let script = """
        import json, os, subprocess, sys, types
        environment = {"BUILT_PRODUCTS_DIR": \(pythonString(root.appending(component: "products").pathString))}
        mappings = \(prefixMapping ? "{'/^root': '/consumer'}" : "{}")
        compiler_precedence = lambda mapping: -len(mapping[1])
        plan = {"mappings": [[\(pythonString(producer)), "/consumer/Feature.swift"]], "artifacts": [],
                "nativeProducts": ["Feature.framework"], "requiresLinkedDebugInformation": False}
        listed_sources = []
        def run(arguments, **kwargs):
            if arguments == ["/usr/bin/xcrun", "--find", "dwarfdump"]:
                return types.SimpleNamespace(stdout="/toolchain/dwarfdump\\n")
            assert arguments[0] == "/toolchain/dwarfdump"
            assert len(arguments) == 3
            if arguments[1] == "--show-sources":
                listed_sources.append(arguments[2])
            output = \(pythonString(observedSource +
                    "\n")) if arguments[1] == "--show-sources" else "UUID: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (arm64)\\n"
            return types.SimpleNamespace(stdout=output)
        subprocess.run = run
        \(CachedModuleSymbolsPreparationScript.value)
        print(len(listed_sources))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: String(decoding: diagnostics, as: UTF8.self)))
        return try #require(Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func pythonString(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n") + "'"
    }

    private func writePlist(_ info: [String: Any], at path: AbsolutePath) throws {
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: path.url)
    }

    private func readPlist(_ path: AbsolutePath) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: path.url), format: nil) as? [String: Any])
    }
}
