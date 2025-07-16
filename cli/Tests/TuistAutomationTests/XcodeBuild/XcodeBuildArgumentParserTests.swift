import Foundation
import Testing
import TuistSupport
import XcodeGraph

@testable import TuistAutomation

struct XcodeBuildArgumentParserTests {
    private let subject = XcodeBuildArgumentParser()

    @Test
    func parse_with_no_destination() async throws {
        // When
        let got = try await subject.parse(["-scheme", "MyScheme"])

        // Then
        #expect(
            got == .test(destination: nil)
        )
    }

    @Test
    func parse_with_destination_name_and_os() async throws {
        // When
        let got = try await subject.parse(["-scheme", "MyScheme", "-destination", "name=iPhone 16,OS=16.0"])

        // Then
        #expect(
            got == .test(
                destination: XcodeBuildArguments.Destination(
                    name: "iPhone 16",
                    platform: nil,
                    id: nil,
                    os: Version(16, 0, 0)
                )
            )
        )
    }

    @Test
    func parse_with_destination_id() async throws {
        // When
        let got = try await subject.parse(["-scheme", "MyScheme", "-destination", "id=some-id"])

        // Then
        #expect(
            got == .test(
                destination: XcodeBuildArguments.Destination(
                    name: nil,
                    platform: nil,
                    id: "some-id",
                    os: nil
                )
            )
        )
    }

    @Test(.withMockedEnvironment())
    func parse_with_workspace() async throws {
        // When
        let got = try await subject.parse(["-scheme", "MyScheme", "-workspace", "App.xcworkspace"])

        // Then
        #expect(
            got == .test(
                workspacePath: try await Environment.current.currentWorkingDirectory().appending(component: "App.xcworkspace")
            )
        )
    }

    @Test(.withMockedEnvironment())
    func parse_with_project() async throws {
        // When
        let got = try await subject.parse(["-scheme", "MyScheme", "-project", "App.xcodeproj"])

        // Then
        #expect(
            got == .test(
                projectPath: try await Environment.current.currentWorkingDirectory().appending(component: "App.xcodeproj")
            )
        )
    }

    @Test(.withMockedEnvironment())
    func parse_with_derived_data_path() async throws {
        // When
        let got = try await subject.parse(["-scheme", "MyScheme", "-derivedDataPath", "DerivedData"])

        // Then
        #expect(
            got == .test(
                derivedDataPath: try await Environment.current.currentWorkingDirectory().appending(component: "DerivedData")
            )
        )
    }

    @Test
    func parse_with_invalid_destination() async throws {
        // When
        let got = try await subject.parse(["-scheme", "MyScheme", "-destination", "invalid_value=some-id"])

        // Then
        #expect(
            got == .test(
                destination: XcodeBuildArguments.Destination(
                    name: nil,
                    platform: nil,
                    id: nil,
                    os: nil
                )
            )
        )
    }
}
