import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class SwiftPackageManagerControllerTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerController!

    override func setUp() {
        super.setUp()

        subject = SwiftPackageManagerController()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_resolve() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "resolve",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.resolve(at: path))
    }

    func test_update() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "update",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.update(at: path))
    }

    func test_setToolsVersion_specificVersion() throws {
        // Given
        let path = try temporaryPath()
        let version = "5.4"
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "tools-version",
            "--set",
            version,
        ])

        // When / Then
        XCTAssertNoThrow(try subject.setToolsVersion(at: path, to: version))
    }

    func test_setToolsVersion_currentVersion() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "tools-version",
            "--set-current",
        ])

        // When / Then
        XCTAssertNoThrow(try subject.setToolsVersion(at: path, to: nil))
    }

    func test_loadPackageInfo() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(
            [
                "swift",
                "package",
                "--package-path",
                path.pathString,
                "dump-package",
            ],
            output: Self.testPackageInfoJSON
        )

        // When
        let packageInfo = try subject.loadPackageInfo(at: path)

        // Then
        XCTAssertEqual(packageInfo, Self.testPackageInfo)
    }
}

extension SwiftPackageManagerControllerTests {
    static let testPackageInfoJSON = """
    {
      "cLanguageStandard" : "something",
      "cxxLanguageStandard" : null,
      "dependencies" : [
        {
          "name" : "a-dependency",
          "productFilter" : null,
          "requirement" : {
            "range" : [
              {
                "lowerBound" : "0.4.0",
                "upperBound" : "1.0.0"
              }
            ]
          },
          "url" : "https://github.com/tuist/a-dependency"
        },
        {
          "name" : "another-dependency",
          "productFilter" : null,
          "requirement" : {
            "range" : [
              {
                "lowerBound" : "0.1.3",
                "upperBound" : "1.0.0"
              }
            ]
          },
          "url" : "https://github.com/tuist/another-dependency"
        }
      ],
      "name" : "tuist",
      "packageKind" : "root",
      "pkgConfig" : null,
      "platforms" : [
        {
          "options" : [

          ],
          "platformName" : "ios",
          "version" : "13.0"
        },
        {
          "options" : [

          ],
          "platformName" : "macos",
          "version" : "10.15"
        },
        {
          "options" : [

          ],
          "platformName" : "tvos",
          "version" : "13.0"
        },
        {
          "options" : [

          ],
          "platformName" : "watchos",
          "version" : "6.0"
        }
      ],
      "products" : [
        {
          "name" : "Tuist",
          "targets" : [
            "TuistTuist"
          ],
          "type" : {
            "library" : [
              "automatic"
            ]
          }
        }
      ],
      "providers" : null,
      "swiftLanguageVersions" : null,
      "targets" : [
        {
          "dependencies" : [
            {
              "target" : [
                "TuistKit",
                null
              ]
            },
            {
              "product" : [
                "ALibrary",
                "a-dependency",
                null
              ]
            },
          ],
          "exclude" : [

          ],
          "name" : "Tuist",
          "path": "customPath",
          "sources": [
            "customSources"
          ],
          "resources" : [
            {
              "rule": "copy",
              "path": "resources"
            }
          ],
          "settings" : [
            {
              "tool": "swift",
              "name": "linkedLibrary",
              "value": [
                "settingValue"
              ]
            }

          ],
          "type" : "regular"
        },
        {
          "dependencies" : [
            {
              "byName" : [
                "AnotherLibrary",
                null
              ]
            }
          ],
          "exclude" : [

          ],
          "name" : "TuistKit",
          "resources" : [

          ],
          "settings" : [

          ],
          "type" : "regular"
        },
        {
          "dependencies" : [
            {
              "byName" : [
                "TuistKit",
                null
              ]
            }
          ],
          "exclude" : [

          ],
          "name" : "TuistKitTests",
          "resources" : [

          ],
          "settings" : [

          ],
          "type" : "test"
        }
      ],
      "toolsVersion" : {
        "_version" : "5.1.0"
      }
    }

    """

    static let testPackageInfo = PackageInfo(
        platforms: [
            .init(platformName: "ios", version: "13.0", options: []),
            .init(platformName: "macos", version: "10.15", options: []),
            .init(platformName: "tvos", version: "13.0", options: []),
            .init(platformName: "watchos", version: "6.0", options: []),
        ],
        targets: [
            .init(
                name: "Tuist",
                path: "customPath",
                url: nil,
                sources: [
                    "customSources",
                ],
                resources: [
                    .init(rule: .copy, path: "resources")
                ],
                exclude: [],
                dependencies: [
                    .target(name: "TuistKit", condition: nil),
                    .product(name: "ALibrary", package: "a-dependency", condition: nil),
                ],
                publicHeadersPath: nil,
                type: .regular,
                settings: [
                    .init(tool: .swift, name: .linkedLibrary, condition: nil, value: ["settingValue"])
                ],
                checksum: nil
            ),
            .init(
                name: "TuistKit",
                path: nil,
                url: nil,
                sources: nil,
                resources: [],
                exclude: [],
                dependencies: [
                    .byName(name: "AnotherLibrary", condition: nil),
                ],
                publicHeadersPath: nil,
                type: .regular,
                settings: [],
                checksum: nil
            ),
            .init(
                name: "TuistKitTests",
                path: nil,
                url: nil,
                sources: nil,
                resources: [],
                exclude: [],
                dependencies: [
                    .byName(name: "TuistKit", condition: nil),
                ],
                publicHeadersPath: nil,
                type: .test,
                settings: [],
                checksum: nil
            )
        ]
    )
}
