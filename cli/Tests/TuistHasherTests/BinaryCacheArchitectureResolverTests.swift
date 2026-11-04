import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistHasher

struct BinaryCacheArchitectureResolverTests {
    @Test(.inTemporaryDirectory) func xcconfigExclusionNarrowsOnlyTheMatchingSDK() async throws {
        let target = try await target(projectXCConfig: "EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64 // arm64 Macs only")
        let subject = BinaryCacheArchitectureResolver()
        #expect(try await subject.architectures(of: target, variant: .iosSimulator) == [.arm64])
        #expect(try await subject.architectures(of: target, variant: .iosDevice) == [.arm64])
        #expect(try await subject.architectures(of: target, variant: .macos) == [.arm64, .x8664])
    }

    @Test(.inTemporaryDirectory) func includedXCConfigsAndInheritedValuesCompose() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        try "EXCLUDED_ARCHS = i386\n".write(
            to: directory.appending(component: "Shared.xcconfig").url,
            atomically: true,
            encoding: .utf8
        )
        let target = try await target(
            projectXCConfig: "#include \"Shared.xcconfig\"\n#include? \"Missing.xcconfig\"\nARCHS = $(ARCHS_STANDARD)",
            targetSettings: ["EXCLUDED_ARCHS[sdk=iphonesimulator*]": "$(inherited) x86_64"]
        )
        #expect(try await BinaryCacheArchitectureResolver().architectures(of: target, variant: .iosSimulator) == [.arm64])
    }

    @Test(.inTemporaryDirectory) func environmentXCConfigOverridesTheProject() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let environment = directory.appending(component: "Environment.xcconfig")
        let target = try await target(projectXCConfig: "EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64")
        try "EXCLUDED_ARCHS[sdk=iphonesimulator*] =\n".write(to: environment.url, atomically: true, encoding: .utf8)
        #expect(try await BinaryCacheArchitectureResolver(environmentXCConfig: environment)
            .architectures(of: target, variant: .iosSimulator) == [.arm64, .x8664])
        try "EXCLUDED_ARCHS = x86_64\n".write(to: environment.url, atomically: true, encoding: .utf8)
        #expect(try await BinaryCacheArchitectureResolver(environmentXCConfig: environment)
            .architectures(of: try await self.target(), variant: .iosSimulator) == [.arm64])
    }

    @Test(.inTemporaryDirectory, arguments: [
        "ARCHS = $(NATIVE_ARCH_ACTUAL)",
        "EXCLUDED_ARCHS[arch=x86_64] = x86_64",
        "EXCLUDED_ARCHS[sdk=iphonesimulator26.0] = x86_64",
        "EXCLUDED_ARCHS[sdk=iphonesimulator*][arch=*] = x86_64",
        "VALID_ARCHS = arm64",
        "ARCHS = arm64 x86_64\nEXCLUDED_ARCHS = arm64 x86_64",
        "#include \"Missing.xcconfig\"",
    ])
    func settingsItCannotEvaluateExactlyAreUnknown(xcconfig: String) async throws {
        let target = try await target(projectXCConfig: xcconfig)
        #expect(try await BinaryCacheArchitectureResolver().architectures(of: target, variant: .iosSimulator) == nil)
    }

    @Test(.inTemporaryDirectory) func configurationsThatDisagreeAreUnknown() async throws {
        let target = try await target(
            projectXCConfig: "EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64",
            configurations: [.debug("Debug"), .release("Release")]
        )
        #expect(try await BinaryCacheArchitectureResolver().architectures(of: target, variant: .iosSimulator) == nil)
    }

    private func target(
        projectXCConfig: String? = nil,
        targetSettings: SettingsDictionary = [:],
        configurations: [BuildConfiguration] = [.debug("Debug")]
    ) async throws -> GraphTarget {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        var xcconfig: AbsolutePath?
        if let projectXCConfig {
            let path = directory.appending(component: "Project.xcconfig")
            try projectXCConfig.write(to: path.url, atomically: true, encoding: .utf8)
            xcconfig = path
        }
        let projectConfigurations = Dictionary(uniqueKeysWithValues: configurations.enumerated().map {
            ($0.element, Optional(Configuration(settings: [:], xcconfig: $0.offset == 0 ? xcconfig : nil)))
        })
        let target = Target.test(
            name: "Feature", destinations: [.iPhone, .mac], product: .framework,
            settings: Settings(base: targetSettings, configurations: [:])
        )
        let project = Project.test(path: directory, settings: Settings(configurations: projectConfigurations), targets: [target])
        return GraphTarget(path: directory, target: target, project: project)
    }
}
