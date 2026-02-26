import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXBuildRuleMapperTests {
    let mapper = PBXBuildRuleMapper()

    @Test("Maps build rules with known compiler spec and file type successfully")
    func mapBuildRulesWithKnownCompilerSpecAndFileType() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj
        let knownCompilerSpec = BuildRule.CompilerSpec.appleClang.rawValue
        let knownFileType = BuildRule.FileType.cSource.rawValue

        let buildRule = PBXBuildRule.test(
            compilerSpec: knownCompilerSpec,
            fileType: knownFileType,
            filePatterns: "*.c",
            name: "C Rule",
            outputFiles: ["$(DERIVED_FILE_DIR)/output.c.o"],
            inputFiles: ["$(SRCROOT)/main.c"],
            outputFilesCompilerFlags: ["-O2"],
            script: "echo Building C sources",
            runOncePerArchitecture: false
        ).add(to: pbxProj)

        try PBXNativeTarget.test(buildRules: [buildRule])
            .add(to: pbxProj)
            .add(to: pbxProj.rootObject)

        // When
        let optionalRule = try mapper.map(buildRule)

        // Then
        let rule = try #require(optionalRule)
        #expect(rule.compilerSpec.rawValue == knownCompilerSpec)
        #expect(rule.fileType.rawValue == knownFileType)
        #expect(rule.filePatterns == "*.c")
        #expect(rule.name == "C Rule")
        #expect(rule.outputFiles == ["$(DERIVED_FILE_DIR)/output.c.o"])
        #expect(rule.inputFiles == ["$(SRCROOT)/main.c"])
        #expect(rule.outputFilesCompilerFlags == ["-O2"])
        #expect(rule.script == "echo Building C sources")
        #expect(rule.runOncePerArchitecture == false)
    }

    @Test("Skips build rules when compiler spec is unknown")
    func mapBuildRulesWithUnknownCompilerSpec() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj
        let unknownCompilerSpec = "com.apple.compilers.unknown"
        let knownFileType = "sourcecode.c.c"

        let buildRule = PBXBuildRule.test(
            compilerSpec: unknownCompilerSpec,
            fileType: knownFileType
        ).add(to: pbxProj)

        try PBXNativeTarget.test(buildRules: [buildRule])
            .add(to: pbxProj)
            .add(to: pbxProj.rootObject)

        // When / Then
        #expect(throws: PBXBuildRuleMappingError.unknownCompilerSpec("com.apple.compilers.unknown")) {
            try mapper.map(buildRule)
        }
    }

    @Test("Skips build rules when file type is unknown")
    func mapBuildRulesWithUnknownFileType() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj
        let knownCompilerSpec = BuildRule.CompilerSpec.appleClang.rawValue
        let unknownFileType = "sourcecode.unknown"

        let buildRule = PBXBuildRule.test(
            compilerSpec: knownCompilerSpec,
            fileType: unknownFileType
        ).add(to: pbxProj)

        try PBXNativeTarget.test(buildRules: [buildRule])
            .add(to: pbxProj)
            .add(to: pbxProj.rootObject)

        // When / Then
        #expect(throws: PBXBuildRuleMappingError.unknownFileType("sourcecode.unknown")) {
            try mapper.map(buildRule)
        }
    }

    @Test("Individually handles valid and invalid rules, returning nil for invalid ones")
    func mapIndividualValidAndInvalidRules() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj
        let knownCompilerSpec = BuildRule.CompilerSpec.appleClang.rawValue
        let knownFileType = BuildRule.FileType.cSource.rawValue
        let unknownCompilerSpec = "com.apple.compilers.unknown"
        let unknownFileType = "sourcecode.unknown"

        let validRule = PBXBuildRule.test(
            compilerSpec: knownCompilerSpec,
            fileType: knownFileType,
            name: "Valid Rule"
        ).add(to: pbxProj)

        let invalidRuleUnknownCompiler = PBXBuildRule.test(
            compilerSpec: unknownCompilerSpec,
            fileType: knownFileType,
            name: "Invalid Compiler"
        ).add(to: pbxProj)

        let invalidRuleUnknownFileType = PBXBuildRule.test(
            compilerSpec: knownCompilerSpec,
            fileType: unknownFileType,
            name: "Invalid FileType"
        ).add(to: pbxProj)

        try PBXNativeTarget.test(
            buildRules: [validRule, invalidRuleUnknownCompiler, invalidRuleUnknownFileType]
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // When / Then
        // Valid rule
        let validResult = try mapper.map(validRule)
        #expect(validResult?.name == "Valid Rule")

        // When / Then
        // Invalid (unknown compiler)
        #expect(throws: PBXBuildRuleMappingError.unknownCompilerSpec("com.apple.compilers.unknown")) {
            try mapper.map(invalidRuleUnknownCompiler)
        }

        // When / Then
        // Invalid (unknown file type)
        #expect(throws: PBXBuildRuleMappingError.unknownFileType("sourcecode.unknown")) {
            try mapper.map(invalidRuleUnknownFileType)
        }
    }
}
