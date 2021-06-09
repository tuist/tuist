@testable import TuistDependencies

extension PackageInfo {
    static var testJSON: String {
        """
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
    }

    static var test: PackageInfo {
        return .init(
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
}
