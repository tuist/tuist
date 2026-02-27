import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXScriptsBuildPhaseMapperTests {
    @Test("Maps embedded run scripts with specified input/output paths")
    func mapScripts() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let scriptPhase = PBXShellScriptBuildPhase.test(
            name: "Run Script",
            shellScript: "echo Hello",
            inputPaths: ["$(SRCROOT)/input.txt"],
            outputPaths: ["$(DERIVED_FILE_DIR)/output.txt"],
            inputFileListPaths: ["${PODS_ROOT}/${CONFIGURATION}/file-list.xcfilelist"]
        )
        .add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            buildPhases: [scriptPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let mapper = PBXScriptsBuildPhaseMapper()

        // When
        let scripts = try mapper.map([scriptPhase], buildPhases: [scriptPhase])

        // Then
        #expect(scripts.count == 1)
        let script = try #require(scripts.first)
        #expect(script.name == "Run Script")
        #expect(script.script == .embedded("echo Hello"))
        #expect(script.inputPaths == ["$(SRCROOT)/input.txt"])
        #expect(script.outputPaths == ["$(DERIVED_FILE_DIR)/output.txt"])
        #expect(script.inputFileListPaths == ["${PODS_ROOT}/${CONFIGURATION}/file-list.xcfilelist"])
    }

    @Test("Maps raw script build phases not covered by other categories")
    func mapRawScriptBuildPhases() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let scriptPhase = PBXShellScriptBuildPhase.test(
            name: "Test Script"
        )
        .add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            buildPhases: [scriptPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let mapper = PBXScriptsBuildPhaseMapper()

        // When
        let rawPhases = try mapper.map([scriptPhase], buildPhases: [scriptPhase])

        // Then
        #expect(rawPhases.count == 1)
        let rawPhase = try #require(rawPhases.first)
        #expect(rawPhase.name == "Test Script")
    }
}
