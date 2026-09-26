import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistEnvironment
import TuistTesting
import XCResultParser
@testable import TuistKit

struct TestEnumerationServiceTests {
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let subject: TestEnumerationService

    init() {
        subject = TestEnumerationService(xcodeBuildController: xcodeBuildController)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func writesTheTestsXcodebuildListsIntoTheResultBundle() async throws {
        let bundle = try #require(FileSystem.temporaryTestDirectory).appending(component: "run.xcresult")
        try await FileSystem().makeDirectory(at: bundle)
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        given(xcodeBuildController)
            .enumerateTests(
                .any, scheme: .any, destination: .any, rosetta: .any, derivedDataPath: .any, testPlan: .any,
                passthroughXcodeBuildArguments: .any, outputPath: .any
            )
            .willProduce { _, _, _, _, _, _, _, outputPath in
                let output = #"{"errors":[],"values":[{"enabledTests":[{"identifier":"AppTests/MathTests/testAdd()"}]}]}"#
                try Data(output.utf8).write(to: URL(fileURLWithPath: outputPath.pathString))
            }

        let enumeration = await subject.record(
            resultBundlePath: bundle, target: nil, scheme: "App", destination: nil, rosetta: false,
            derivedDataPath: nil, testPlan: nil, xcodebuildArguments: ["test"]
        )

        let expected = TestEnumeration(tests: [.init(module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true)])
        #expect(enumeration == expected)
        #expect(TestEnumeration.read(fromResultBundle: URL(fileURLWithPath: bundle.pathString)) == expected)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func leavesTheRunAloneWhenTheTestsCannotBeListed() async throws {
        let bundle = try #require(FileSystem.temporaryTestDirectory).appending(component: "run.xcresult")
        try await FileSystem().makeDirectory(at: bundle)
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        given(xcodeBuildController)
            .enumerateTests(
                .any, scheme: .any, destination: .any, rosetta: .any, derivedDataPath: .any, testPlan: .any,
                passthroughXcodeBuildArguments: .any, outputPath: .any
            )
            .willThrow(TestEnumerationError.timedOut(1))

        let enumeration = await subject.record(
            resultBundlePath: bundle, target: nil, scheme: nil, destination: nil, rosetta: false,
            derivedDataPath: nil, testPlan: nil, xcodebuildArguments: []
        )

        #expect(enumeration == nil)
        #expect(TestEnumeration.read(fromResultBundle: URL(fileURLWithPath: bundle.pathString)) == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func listsNothingWithoutTheClientFlag() async throws {
        let bundle = try #require(FileSystem.temporaryTestDirectory).appending(component: "run.xcresult")
        try await FileSystem().makeDirectory(at: bundle)

        let enumeration = await subject.record(
            resultBundlePath: bundle, target: nil, scheme: "App", destination: nil, rosetta: false,
            derivedDataPath: nil, testPlan: nil, xcodebuildArguments: ["test"]
        )

        #expect(enumeration == nil)
        verify(xcodeBuildController)
            .enumerateTests(
                .any, scheme: .any, destination: .any, rosetta: .any, derivedDataPath: .any, testPlan: .any,
                passthroughXcodeBuildArguments: .any, outputPath: .any
            )
            .called(0)
    }

    @Test func theTimeoutComesFromTheEnvironmentAndZeroTurnsItOff() {
        #expect(TestEnumerationService.timeout(variables: [:]) == 60)
        #expect(TestEnumerationService.timeout(variables: ["TUIST_TEST_ENUMERATION_TIMEOUT_SECONDS": "5"]) == 5)
        #expect(TestEnumerationService.timeout(variables: ["TUIST_TEST_ENUMERATION_TIMEOUT_SECONDS": "0"]) == 0)
        #expect(TestEnumerationService.timeout(variables: ["TUIST_TEST_ENUMERATION_TIMEOUT_SECONDS": "soon"]) == 60)
    }
}
