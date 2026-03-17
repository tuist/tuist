#if os(macOS)
    import FileSystem
    import FileSystemTesting
    import Foundation
    import Path
    import Testing
    import TuistSupport

    @testable import TuistAutomation
    @testable import TuistTesting

    struct XCTestRunParserTests {
        let subject = XCTestRunParser()

        // MARK: - parseTestModules

        @Test(.inTemporaryDirectory)
        func parseTestModules_parsesTargets() async throws {
            // Given
            let path = try writePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "AppTests"],
                            ["BlueprintName": "CoreTests"],
                        ],
                    ],
                ],
            ])

            // When
            let modules = try await subject.parseTestModules(xctestrunPath: path)

            // Then
            #expect(modules == ["AppTests", "CoreTests"])
        }

        @Test(.inTemporaryDirectory)
        func parseTestModules_multipleConfigurations() async throws {
            // Given
            let path = try writePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "UnitTests"],
                        ],
                    ],
                    [
                        "TestTargets": [
                            ["BlueprintName": "UITests"],
                        ],
                    ],
                ],
            ])

            // When
            let modules = try await subject.parseTestModules(xctestrunPath: path)

            // Then
            #expect(modules == ["UnitTests", "UITests"])
        }

        // MARK: - parseTestSuites

        @Test(.inTemporaryDirectory)
        func parseTestSuites_withOnlyTestIdentifiers() async throws {
            // Given
            let path = try writePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            [
                                "BlueprintName": "AppTests",
                                "OnlyTestIdentifiers": ["LoginTests/testLogin", "LoginTests/testLogout"],
                            ],
                            [
                                "BlueprintName": "CoreTests",
                                "OnlyTestIdentifiers": ["NetworkTests/testFetch"],
                            ],
                        ],
                    ],
                ],
            ])

            // When
            let suites = try await subject.parseTestSuites(xctestrunPath: path)

            // Then
            #expect(suites["AppTests"] == ["LoginTests/testLogin", "LoginTests/testLogout"])
            #expect(suites["CoreTests"] == ["NetworkTests/testFetch"])
        }

        @Test(.inTemporaryDirectory)
        func parseTestSuites_withoutOnlyTestIdentifiers() async throws {
            // Given
            let path = try writePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "AppTests"],
                        ],
                    ],
                ],
            ])

            // When
            let suites = try await subject.parseTestSuites(xctestrunPath: path)

            // Then
            #expect(suites.isEmpty)
        }

        // MARK: - Error cases

        @Test(.inTemporaryDirectory)
        func parseTestModules_throwsForInvalidPlist() async throws {
            // Given
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let path = temporaryDirectory.appending(component: "Invalid.xctestrun")
            try Data("not a plist".utf8).write(to: URL(fileURLWithPath: path.pathString))

            // When / Then
            await #expect(throws: XCTestRunParserError.self) {
                try await subject.parseTestModules(xctestrunPath: path)
            }
        }

        @Test(.inTemporaryDirectory)
        func parseTestModules_throwsForMissingFile() async throws {
            // Given
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let path = temporaryDirectory.appending(component: "Missing.xctestrun")

            // When / Then
            await #expect(throws: XCTestRunParserError.self) {
                try await subject.parseTestModules(xctestrunPath: path)
            }
        }

        // MARK: - Helpers

        private func writePlist(_ dict: [String: Any]) throws -> AbsolutePath {
            let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
            let path = temporaryDirectory.appending(component: "Test.xctestrun")
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .xml,
                options: 0
            )
            try data.write(to: URL(fileURLWithPath: path.pathString))
            return path
        }
    }
#endif
