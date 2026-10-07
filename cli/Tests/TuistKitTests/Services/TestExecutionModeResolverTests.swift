import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistEnvironment
import TuistTesting
import XCResultParser
@testable import TuistKit

struct TestExecutionModeResolverTests {
    private let subject = TestExecutionModeResolver()

    @Test func theCommandLineDecidesForEveryTarget() {
        let targets = ["AppTests": "parallel", "CoreTests": "serial"]

        #expect(
            TestExecutionModeResolver.resolve(xcodebuildArguments: ["test", "-parallel-testing-enabled", "NO"], targets: targets)
                == TestExecutionModes(run: "serial", targets: ["AppTests": "serial", "CoreTests": "serial"])
        )
        #expect(
            TestExecutionModeResolver.resolve(xcodebuildArguments: ["-parallel-testing-enabled", "YES"], targets: [:])
                == TestExecutionModes(run: "parallel", targets: [:])
        )
    }

    @Test func theTargetsDecideOtherwiseAndNothingIsGuessed() {
        #expect(
            TestExecutionModeResolver.resolve(
                xcodebuildArguments: ["test"],
                targets: ["AppTests": "parallel", "CoreTests": "serial"]
            )
                == TestExecutionModes(run: "parallel", targets: ["AppTests": "parallel", "CoreTests": "serial"])
        )
        #expect(
            TestExecutionModeResolver.resolve(xcodebuildArguments: ["test"], targets: ["CoreTests": "serial"])
                == TestExecutionModes(run: "serial", targets: ["CoreTests": "serial"])
        )
        #expect(TestExecutionModeResolver.resolve(xcodebuildArguments: ["test"], targets: [:]) == nil)
    }

    @Test func readsParallelizationFromBothXctestrunFormats() throws {
        let versionTwo: [String: Any] = [
            "__xctestrun_metadata__": ["FormatVersion": 2],
            "TestConfigurations": [
                [
                    "Name": "Configuration 1",
                    "TestTargets": [
                        ["BlueprintName": "AppTests", "ParallelizationEnabled": true],
                        ["BlueprintName": "CoreTests"],
                    ],
                ],
            ],
        ]
        let versionOne: [String: Any] = [
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": ["ProductModuleName": "AppTests", "ParallelizationEnabled": false],
        ]

        #expect(
            try TestExecutionModeResolver.parallelizationByTarget(
                xctestrun: PropertyListSerialization.data(fromPropertyList: versionTwo, format: .xml, options: 0)
            ) == ["AppTests": true, "CoreTests": false]
        )
        #expect(
            try TestExecutionModeResolver.parallelizationByTarget(
                xctestrun: PropertyListSerialization.data(fromPropertyList: versionOne, format: .xml, options: 0)
            ) == ["AppTests": false]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func recordsTheModesFromTheDerivedDataIntoTheBundle() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let derivedData = directory.appending(component: "DerivedData")
        let products = derivedData.appending(components: "Build", "Products")
        try FileManager.default.createDirectory(atPath: products.pathString, withIntermediateDirectories: true)
        let xctestrun: [String: Any] = [
            "__xctestrun_metadata__": ["FormatVersion": 2],
            "TestConfigurations": [["TestTargets": [["BlueprintName": "AppTests", "ParallelizationEnabled": true]]]],
        ]
        try PropertyListSerialization.data(fromPropertyList: xctestrun, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: products.appending(component: "App_iphonesimulator.xctestrun").pathString))
        let bundle = directory.appending(component: "Run.xcresult")
        try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)

        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let modes = await subject.record(
            resultBundlePath: bundle,
            xcodebuildArguments: ["test"],
            derivedDataPath: derivedData,
            schemeTargets: [:]
        )

        #expect(modes == TestExecutionModes(run: "parallel", targets: ["AppTests": "parallel"]))
        #expect(TestExecutionModes.read(fromResultBundle: URL(fileURLWithPath: bundle.pathString)) == modes)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func recordsNothingWithoutTheClientFlag() async throws {
        let bundle = try #require(FileSystem.temporaryTestDirectory).appending(component: "Run.xcresult")
        try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)

        let modes = await subject.record(
            resultBundlePath: bundle,
            xcodebuildArguments: ["test", "-parallel-testing-enabled", "NO"],
            derivedDataPath: nil,
            schemeTargets: [:]
        )

        #expect(modes == nil)
        #expect(TestExecutionModes.read(fromResultBundle: URL(fileURLWithPath: bundle.pathString)) == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func recordsNothingWithoutAnXctestrunOrAFlag() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let bundle = directory.appending(component: "Run.xcresult")
        try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)

        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let modes = await subject.record(
            resultBundlePath: bundle,
            xcodebuildArguments: ["test"],
            derivedDataPath: nil,
            schemeTargets: [:]
        )

        #expect(modes == nil)
        #expect(TestExecutionModes.read(fromResultBundle: URL(fileURLWithPath: bundle.pathString)) == nil)
    }

    @Test func readsTheSchemeFileAndItsTestPlans() throws {
        let scheme = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme version="1.7">
           <TestAction buildConfiguration="Debug">
              <TestPlans>
                 <TestPlanReference reference="container:App.xctestplan" default="YES"/>
              </TestPlans>
              <Testables>
                 <TestableReference skipped="NO" parallelizable="NO">
                    <BuildableReference BlueprintName="AppTests" BlueprintIdentifier="1"/>
                 </TestableReference>
                 <TestableReference skipped="NO" parallelizable="YES">
                    <BuildableReference BlueprintName="CoreTests" BlueprintIdentifier="2"/>
                 </TestableReference>
                 <TestableReference skipped="NO">
                    <BuildableReference BlueprintName="SwiftTests" BlueprintIdentifier="3"/>
                 </TestableReference>
              </Testables>
           </TestAction>
           <LaunchAction>
              <BuildableProductRunnable>
                 <BuildableReference BlueprintName="App" BlueprintIdentifier="0"/>
              </BuildableProductRunnable>
           </LaunchAction>
        </Scheme>
        """
        let parsed = TestExecutionModeResolver.parseScheme(Data(scheme.utf8))
        #expect(parsed.targets == ["AppTests": "serial", "CoreTests": "parallel", "SwiftTests": "parallel"])
        #expect(parsed.testPlans == ["container:App.xctestplan"])

        let plan = """
        {"testTargets": [{"parallelizable": true, "target": {"name": "AppTests"}}, {"target": {"name": "CoreTests"}}]}
        """
        #expect(try TestExecutionModeResolver.parseTestPlan(Data(plan.utf8)) == ["AppTests": "parallel", "CoreTests": "serial"])
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func recordsTheModesFromTheSchemeNamedInTheArguments() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let schemes = directory.appending(components: "App.xcodeproj", "xcshareddata", "xcschemes")
        try FileManager.default.createDirectory(atPath: schemes.pathString, withIntermediateDirectories: true)
        try """
        <Scheme version="1.7"><TestAction><Testables>
        <TestableReference parallelizable="NO"><BuildableReference BlueprintName="AppTests"/></TestableReference>
        </Testables></TestAction></Scheme>
        """.write(toFile: schemes.appending(component: "App.xcscheme").pathString, atomically: true, encoding: .utf8)
        let workspace = directory.appending(component: "App.xcworkspace")
        try FileManager.default.createDirectory(atPath: workspace.pathString, withIntermediateDirectories: true)
        let bundle = directory.appending(component: "Run.xcresult")
        try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)

        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let modes = await subject.record(
            resultBundlePath: bundle,
            xcodebuildArguments: ["-workspace", workspace.pathString, "-scheme", "App", "test"],
            derivedDataPath: nil,
            schemeTargets: ["AppTests": "parallel", "OtherTests": "parallel"]
        )

        // The scheme file refines what the caller knew.
        #expect(modes == TestExecutionModes(run: "parallel", targets: ["AppTests": "serial", "OtherTests": "parallel"]))
        #expect(TestExecutionModes.read(fromResultBundle: URL(fileURLWithPath: bundle.pathString)) == modes)
    }

    @Test func mapsTheGeneratedSchemesParallelization() {
        #expect(TestExecutionModeResolver.mode(for: .none) == "serial")
        #expect(TestExecutionModeResolver.mode(for: .all) == "parallel")
        #expect(TestExecutionModeResolver.mode(for: .swiftTestingOnly) == "parallel")
    }
}
