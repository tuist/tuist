#if os(macOS)
    import Foundation
    import Testing

    @testable import TuistAutomation

    struct XCTestRunTests {
        // MARK: - Format v2 (TestConfigurations)

        @Test
        func decode_v2_parsesTestModules() throws {
            let plist = try makePlist([
                "TestConfigurations": [
                    [
                        "TestTargets": [
                            ["BlueprintName": "AppTests"],
                            ["BlueprintName": "CoreTests"],
                        ],
                    ],
                ],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules == ["AppTests", "CoreTests"])
        }

        @Test
        func decode_v2_multipleConfigurations() throws {
            let plist = try makePlist([
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

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules == ["UnitTests", "UITests"])
        }

        // MARK: - Format v1 (Legacy top-level keys)

        @Test
        func decode_v1_parsesTestModules() throws {
            let plist = try makePlist([
                "__xctestrun_metadata__": ["FormatVersion": 1],
                "AppTests": ["BlueprintName": "AppTests", "TestHostPath": "/path"],
                "CoreTests": ["BlueprintName": "CoreTests", "TestHostPath": "/path"],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(Set(xcTestRun.testModules) == Set(["AppTests", "CoreTests"]))
        }

        @Test
        func decode_v1_skipsMetadataKey() throws {
            let plist = try makePlist([
                "__xctestrun_metadata__": ["FormatVersion": 1, "ContainerInfo": ["SchemeName": "App"]],
                "AppTests": ["BlueprintName": "AppTests"],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules == ["AppTests"])
        }

        @Test
        func decode_v1_emptyTargets() throws {
            let plist = try makePlist([
                "__xctestrun_metadata__": ["FormatVersion": 1],
            ])

            let xcTestRun = try PropertyListDecoder().decode(XCTestRun.self, from: plist)

            #expect(xcTestRun.testModules.isEmpty)
        }

        // MARK: - Helpers

        private func makePlist(_ dict: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        }
    }
#endif
