import Foundation
import Testing
@testable import TuistXCResultService

struct IPSStackTraceParserTests {
    let parser = IPSStackTraceParser()

    @Test
    func triggeredThreadFrames_withValidIPS_returnsFormattedFrames() {
        // Given
        let header = """
        {"app_name":"MyApp","timestamp":"2024-01-15 12:00:00"}
        """
        let payload: [String: Any] = [
            "usedImages": [
                ["name": "libswiftCore.dylib"],
                ["name": "MyApp"],
                ["path": "/usr/lib/system/libdyld.dylib"],
            ],
            "threads": [
                [
                    "triggered": true,
                    "frames": [
                        [
                            "imageIndex": 0,
                            "symbol": "_assertionFailure",
                            "imageOffset": 156,
                        ] as [String: Any],
                        [
                            "imageIndex": 1,
                            "symbol": "MyApp.example()",
                            "imageOffset": 180,
                            "sourceFile": "/Users/dev/MyApp/Sources/App.swift",
                            "sourceLine": 7,
                        ] as [String: Any],
                        [
                            "imageIndex": 2,
                            "imageOffset": 42,
                        ] as [String: Any],
                    ],
                ] as [String: Any],
            ],
        ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(data: payloadData, encoding: .utf8)!
        let content = header + "\n" + payloadString

        // When
        let result = parser.triggeredThreadFrames(content)

        // Then
        #expect(result != nil)
        let lines = result!.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].contains("libswiftCore.dylib"))
        #expect(lines[0].contains("_assertionFailure + 156"))
        #expect(lines[1].contains("MyApp"))
        #expect(lines[1].contains("MyApp.example()"))
        #expect(lines[1].contains("App.swift:7"))
        #expect(lines[2].contains("libdyld.dylib"))
        #expect(lines[2].contains("0x2a"))
    }

    @Test
    func triggeredThreadFrames_withInvalidContent_returnsNil() {
        #expect(parser.triggeredThreadFrames("not valid") == nil)
    }

    @Test
    func triggeredThreadFrames_withEmptyContent_returnsNil() {
        #expect(parser.triggeredThreadFrames("") == nil)
    }

    @Test
    func triggeredThreadFrames_withNoTriggeredThread_usesFirstThread() {
        // Given
        let header = "{}"
        let payload: [String: Any] = [
            "usedImages": [
                ["name": "MyApp"],
            ],
            "threads": [
                [
                    "frames": [
                        [
                            "imageIndex": 0,
                            "symbol": "main",
                            "imageOffset": 100,
                        ] as [String: Any],
                    ],
                ] as [String: Any],
            ],
        ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(data: payloadData, encoding: .utf8)!
        let content = header + "\n" + payloadString

        // When
        let result = parser.triggeredThreadFrames(content)

        // Then
        #expect(result != nil)
        #expect(result!.contains("main + 100"))
    }

    @Test
    func triggeredThreadFrames_withImagePath_extractsLastComponent() {
        // Given
        let header = "{}"
        let payload: [String: Any] = [
            "usedImages": [
                ["path": "/usr/lib/system/libsystem_kernel.dylib"],
            ],
            "threads": [
                [
                    "triggered": true,
                    "frames": [
                        [
                            "imageIndex": 0,
                            "symbol": "__pthread_kill",
                            "imageOffset": 8,
                        ] as [String: Any],
                    ],
                ] as [String: Any],
            ],
        ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(data: payloadData, encoding: .utf8)!
        let content = header + "\n" + payloadString

        // When
        let result = parser.triggeredThreadFrames(content)

        // Then
        #expect(result != nil)
        #expect(result!.contains("libsystem_kernel.dylib"))
    }
}
