import Path
import Testing
import TuistSupport
import XcodeGraph

@testable import TuistCache
@testable import TuistTesting

struct CacheWarmForeignBuildOutputValidatorTests {
    private let subject = CacheWarmForeignBuildOutputValidator()

    @Test func validateAcceptsForeignBuildTargetsWithTemporaryScratchDirectory() throws {
        try subject.validate(
            targets: [
                try foreignBuildGraphTarget(name: "Foreign"),
                targetScriptGraphTarget(name: "Script"),
            ],
            scratchDirectory: .temporary
        )
    }

    @Test func validateAcceptsRegularTargetsWithCallerOwnedScratchDirectory() throws {
        try subject.validate(
            targets: [GraphTarget.test(target: .test(name: "Regular"))],
            scratchDirectory: .callerOwned(try AbsolutePath(validating: "/scratch"))
        )
    }

    @Test func validateRejectsForeignBuildTargetsWithCallerOwnedScratchDirectory() throws {
        let scratchDirectory = try AbsolutePath(validating: "/scratch")

        #expect(throws: CacheWarmForeignBuildOutputValidatorError.unsupported(
            scratchDirectory: scratchDirectory,
            targetNames: ["ForeignA", "ForeignB"]
        )) {
            try subject.validate(
                targets: [
                    try foreignBuildGraphTarget(name: "ForeignB"),
                    try foreignBuildGraphTarget(name: "ForeignA"),
                ],
                scratchDirectory: .callerOwned(scratchDirectory)
            )
        }
    }

    @Test func validateRejectsTargetScriptsWithCallerOwnedScratchDirectory() throws {
        let scratchDirectory = try AbsolutePath(validating: "/scratch")

        #expect(throws: CacheWarmForeignBuildOutputValidatorError.unsupportedTargetScripts(
            scratchDirectory: scratchDirectory,
            targetNames: ["ScriptA", "ScriptB"]
        )) {
            try subject.validate(
                targets: [
                    targetScriptGraphTarget(name: "ScriptB"),
                    targetScriptGraphTarget(name: "ScriptA"),
                ],
                scratchDirectory: .callerOwned(scratchDirectory)
            )
        }
    }

    private func targetScriptGraphTarget(name: String) -> GraphTarget {
        GraphTarget.test(
            target: .test(
                name: name,
                scripts: [
                    .init(
                        name: "Write output",
                        order: .post,
                        script: .embedded("touch /outside/artifact"),
                        inputPaths: ["/input"],
                        outputPaths: ["/outside/artifact"]
                    ),
                ]
            )
        )
    }

    private func foreignBuildGraphTarget(name: String) throws -> GraphTarget {
        GraphTarget.test(
            target: .test(
                name: name,
                foreignBuild: ForeignBuild(
                    script: "build",
                    inputs: [],
                    output: .xcframework(
                        path: try AbsolutePath(validating: "/\(name).xcframework"),
                        linking: .dynamic
                    )
                )
            )
        )
    }
}
