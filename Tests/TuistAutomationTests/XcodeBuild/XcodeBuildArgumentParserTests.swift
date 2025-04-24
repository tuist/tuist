import Foundation
import Testing
import XcodeGraph

@testable import TuistAutomation

struct XcodeBuildArgumentParserTests {
    private let subject = XcodeBuildArgumentParser()

    @Test
    func test_parse_with_no_destination() async throws {
        // When
        let got = subject.parse(["-scheme", "MyScheme"])

        // Then
        #expect(
            got == XcodeBuildArguments(destination: nil)
        )
    }

    @Test
    func test_parse_with_destination_name_and_os() async throws {
        // When
        let got = subject.parse(["-scheme", "MyScheme", "-destination", "name=iPhone 16,OS=16.0"])

        // Then
        #expect(
            got == XcodeBuildArguments(
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
    func test_parse_with_destination_id() async throws {
        // When
        let got = subject.parse(["-scheme", "MyScheme", "-destination", "id=some-id"])

        // Then
        #expect(
            got == XcodeBuildArguments(
                destination: XcodeBuildArguments.Destination(
                    name: nil,
                    platform: nil,
                    id: "some-id",
                    os: nil
                )
            )
        )
    }

    @Test
    func test_parse_with_invalid_destination() async throws {
        // When
        let got = subject.parse(["-scheme", "MyScheme", "-destination", "invalid_value=some-id"])

        // Then
        #expect(
            got == XcodeBuildArguments(
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
