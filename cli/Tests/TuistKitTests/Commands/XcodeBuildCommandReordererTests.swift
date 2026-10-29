import ArgumentParser
import Testing
@testable import TuistKit

struct XcodeBuildCommandReordererTests {
    @Test(arguments: [
        ["-workspace", "App.xcworkspace", "-scheme", "App", "-testPlan", "All", "clean", "build", "test"],
        ["-workspace", "App.xcworkspace", "clean", "test"],
        ["-workspace", "App.xcworkspace", "clean", "build-for-testing"],
        ["-workspace", "App.xcworkspace", "clean", "test-without-building"],
        ["-workspace", "App.xcworkspace", "clean", "archive"],
        ["clean", "build", "test", "-scheme", "App"],
        ["clean", "-scheme", "App", "build", "-configuration", "Debug", "test"],
        ["-scheme", "App", "build", "clean", "test"],
        ["-scheme", "App", "build", "build", "test"],
        ["-scheme", "App", "build", "test"],
        ["-scheme", "App", "test", "clean"],
        ["-scheme", "App", "build"],
        ["-scheme", "build", "-testPlan", "test", "clean", "build", "test"],
    ])
    func preservesPassthroughArgumentOrder(arguments: [String]) throws {
        let reorderer = try #require(
            XcodeBuildCommand.parseAsRoot(arguments) as? XcodeBuildCommandReorderer
        )

        let command = try reorderer.reorderedCommand()

        #expect(command.xcodebuildArguments == arguments)
    }

    @Test(arguments: ["build", "build-for-testing", "test", "test-without-building", "archive"])
    func preservesActionFirstArguments(action: String) throws {
        let arguments = [action, "-scheme", "App", "clean", "build", "test"]
        let command = try #require(
            XcodeBuildCommand.parseAsRoot(arguments) as? any XcodeBuildPassthroughCommand
        )

        #expect(command.xcodebuildArguments == arguments)
    }

    @Test
    func preservesOrderWithPassthroughDelimiter() throws {
        let arguments = ["--", "-scheme", "App", "clean", "build", "test"]
        let reorderer = try #require(
            XcodeBuildCommand.parseAsRoot(arguments) as? XcodeBuildCommandReorderer
        )

        let command = try reorderer.reorderedCommand()

        #expect(command.xcodebuildArguments == arguments)
    }

    @Test
    func consumesTuistOptionsWithoutChangingActionOrder() throws {
        let reorderer = try #require(
            XcodeBuildCommand.parseAsRoot([
                "--skip-quarantine", "--inspect-mode", "off",
                "-workspace", "App.xcworkspace", "clean", "test",
            ]) as? XcodeBuildCommandReorderer
        )
        let command = try reorderer.reorderedCommand()
        let testCommand = try #require(command as? XcodeBuildTestCommand)

        #expect(testCommand.skipQuarantine)
        #expect(testCommand.inspectMode == .off)
        #expect(command.xcodebuildArguments == ["-workspace", "App.xcworkspace", "clean", "test"])
    }

    @Test
    func consumesTuistOptionsWhenActionPrecedesPassthroughArguments() throws {
        let reorderer = try #require(
            XcodeBuildCommand.parseAsRoot([
                "--skip-quarantine", "test", "--inspect-mode", "off", "-scheme", "App",
            ]) as? XcodeBuildCommandReorderer
        )
        let command = try reorderer.reorderedCommand()
        let testCommand = try #require(command as? XcodeBuildTestCommand)

        #expect(testCommand.skipQuarantine)
        #expect(testCommand.inspectMode == .off)
        #expect(command.xcodebuildArguments == ["test", "-scheme", "App"])
    }

    @Test
    func consumesShardingOptionsWithoutChangingActionOrder() throws {
        let reorderer = try #require(
            XcodeBuildCommand.parseAsRoot([
                "--shard-total", "3", "-scheme", "App", "clean", "build-for-testing",
            ]) as? XcodeBuildCommandReorderer
        )
        let command = try reorderer.reorderedCommand()
        let buildCommand = try #require(command as? XcodeBuildBuildForTestingCommand)

        #expect(buildCommand.shardTotal == 3)
        #expect(command.xcodebuildArguments == ["-scheme", "App", "clean", "build-for-testing"])
    }

    @Test
    func rejectsEmptyArguments() throws {
        let reorderer = try XcodeBuildCommandReorderer.parse([])

        #expect(throws: ValidationError.self) {
            try reorderer.reorderedCommand()
        }
    }

    @Test
    func rejectsArgumentsWithoutSupportedActions() throws {
        let reorderer = try XcodeBuildCommandReorderer.parse(["-scheme", "App", "clean"])

        #expect(throws: ValidationError.self) {
            try reorderer.reorderedCommand()
        }
    }
}
