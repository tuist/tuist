import Foundation
import Testing
import TuistCore
import XcodeProj
@testable import TuistGenerator

struct RunpathSearchPathsLinterTests {
    private let subject = RunpathSearchPathsLinter()

    @Test func lint_returnsNoIssues_whenBelowTheThreshold() {
        // Given
        let project = ProjectDescriptor.test()
        addTarget(
            named: "AppTests",
            to: project,
            configurations: ["Debug": .array(["$(inherited)"] + runpaths(250))]
        )

        // When
        let got = subject.lint(workspace: .test(projects: [project]))

        // Then
        #expect(got.isEmpty)
    }

    @Test func lint_warnsOnce_forTheLargestConfiguration() throws {
        // Given
        let project = ProjectDescriptor.test()
        addTarget(
            named: "AppTests",
            to: project,
            configurations: [
                "Debug": .array(["$(inherited)"] + runpaths(251)),
                "Release": .array(["$(inherited)"] + runpaths(300)),
            ]
        )

        // When
        let got = subject.lint(workspace: .test(projects: [project]))

        // Then
        let issue = try #require(got.first)
        #expect(got.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.reason.contains("The target 'AppTests' in 'Test.xcodeproj' has 300 run path search paths"))
        #expect(issue.reason.contains("'Release' configuration"))
    }

    @Test func lint_countsInheritedProjectValues_andIgnoresDuplicates() throws {
        // Given
        let project = ProjectDescriptor.test()
        let projectConfiguration = XCBuildConfiguration(
            name: "Debug",
            buildSettings: ["LD_RUNPATH_SEARCH_PATHS": .array(runpaths(200))]
        )
        project.xcodeProj.pbxproj.add(object: projectConfiguration)
        project.xcodeProj.pbxproj.rootObject?.buildConfigurationList.buildConfigurations.append(projectConfiguration)
        addTarget(
            named: "AppTests",
            to: project,
            configurations: ["Debug": .array(["$(inherited)"] + runpaths(100) + runpaths(260).suffix(60))]
        )

        // When
        let got = subject.lint(workspace: .test(projects: [project]))

        // Then
        let issue = try #require(got.first)
        #expect(issue.reason.contains("has 260 run path search paths"))
    }

    @Test func lint_ignoresProjectValues_whenTheTargetDoesNotInherit() {
        // Given
        let project = ProjectDescriptor.test()
        let projectConfiguration = XCBuildConfiguration(
            name: "Debug",
            buildSettings: ["LD_RUNPATH_SEARCH_PATHS": .array(runpaths(300))]
        )
        project.xcodeProj.pbxproj.add(object: projectConfiguration)
        project.xcodeProj.pbxproj.rootObject?.buildConfigurationList.buildConfigurations.append(projectConfiguration)
        addTarget(
            named: "AppTests",
            to: project,
            configurations: ["Debug": .array(["@loader_path/Frameworks"])]
        )

        // When
        let got = subject.lint(workspace: .test(projects: [project]))

        // Then
        #expect(got.isEmpty)
    }

    @Test func lint_splitsStringValues_keepingQuotedPathsTogether() throws {
        // Given
        let project = ProjectDescriptor.test()
        let value = (["$(inherited)", "\"/path with spaces/Frameworks\""] + runpaths(250)).joined(separator: " ")
        addTarget(
            named: "AppTests",
            to: project,
            configurations: ["Debug": .string(value)]
        )

        // When
        let got = subject.lint(workspace: .test(projects: [project]))

        // Then
        let issue = try #require(got.first)
        #expect(issue.reason.contains("has 251 run path search paths"))
    }

    private func runpaths(_ count: Int) -> [String] {
        (0 ..< count).map { "/binaries/\($0)" }
    }

    private func addTarget(
        named name: String,
        to project: ProjectDescriptor,
        configurations: [String: BuildSetting]
    ) {
        let pbxproj = project.xcodeProj.pbxproj
        let configurationList = XCConfigurationList()
        for (configurationName, runpathSearchPaths) in configurations.sorted(by: { $0.key < $1.key }) {
            let configuration = XCBuildConfiguration(
                name: configurationName,
                buildSettings: ["LD_RUNPATH_SEARCH_PATHS": runpathSearchPaths]
            )
            pbxproj.add(object: configuration)
            configurationList.buildConfigurations.append(configuration)
        }
        pbxproj.add(object: configurationList)
        let target = PBXNativeTarget(name: name, buildConfigurationList: configurationList)
        pbxproj.add(object: target)
        pbxproj.rootObject?.targets.append(target)
    }
}
