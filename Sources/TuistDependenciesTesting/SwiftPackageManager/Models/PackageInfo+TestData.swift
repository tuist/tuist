import TSCBasic
import TuistGraph
@testable import TuistDependencies

// MARK: - Test package

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
              "platformName" : "watchos",
              "version" : "6.0"
            }
          ],
          "products" : [
            {
              "name" : "Tuist",
              "targets" : [
                "Tuist"
              ],
              "type" : {
                "library" : [
                  "static"
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
            products: [
                .init(name: "Tuist", type: .library(.static), targets: ["Tuist"]),
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
                        .init(rule: .copy, path: "resources"),
                    ],
                    exclude: [],
                    dependencies: [
                        .target(name: "TuistKit", condition: nil),
                        .product(name: "ALibrary", package: "a-dependency", condition: nil),
                    ],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [
                        .init(tool: .swift, name: .linkedLibrary, condition: nil, value: ["settingValue"]),
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
                ),
            ],
            platforms: [
                .init(platformName: "ios", version: "13.0", options: []),
                .init(platformName: "macos", version: "10.15", options: []),
                .init(platformName: "watchos", version: "6.0", options: []),
            ]
        )
    }

    static var aDependency: PackageInfo {
        return .init(
            products: [
                .init(name: "ALibrary", type: .library(.automatic), targets: ["ALibrary"]),
            ],
            targets: [
                .init(
                    name: "ALibrary",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
            ],
            platforms: [
                .init(platformName: "ios", version: "13.0", options: []),
                .init(platformName: "macos", version: "10.15", options: []),
                .init(platformName: "watchos", version: "6.0", options: []),
            ]
        )
    }

    static var anotherDependency: PackageInfo {
        return .init(
            products: [
                .init(name: "AnotherLibrary", type: .library(.automatic), targets: ["AnotherLibrary"]),
            ],
            targets: [
                .init(
                    name: "AnotherLibrary",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
            ],
            platforms: [
                .init(platformName: "ios", version: "13.0", options: []),
                .init(platformName: "macos", version: "10.15", options: []),
                .init(platformName: "watchos", version: "6.0", options: []),
            ]
        )
    }

    static func testThirdPartyDependency(packageFolder: AbsolutePath) -> ThirdPartyDependency {
        return .sources(
            name: "test",
            products: [
                .init(
                    name: "Tuist",
                    targets: ["Tuist"],
                    libraryType: .static
                ),
            ],
            targets: [
                .init(
                    name: "Tuist",
                    sources: [packageFolder.appending(RelativePath("customPath/customSources"))],
                    resources: [packageFolder.appending(RelativePath("customPath/resources"))],
                    dependencies: [
                        .target(name: "TuistKit"),
                        .thirdPartyTarget(dependency: "a-dependency", product: "ALibrary"),
                    ]
                ),
                .init(
                    name: "TuistKit",
                    sources: [packageFolder.appending(RelativePath("Sources/TuistKit"))],
                    resources: [],
                    dependencies: [
                        .thirdPartyTarget(dependency: "another-dependency", product: "AnotherLibrary"),
                    ]
                ),
            ],
            minDeploymentTargets: [
                .iOS("13.0", .all),
                .macOS("10.15"),
                .watchOS("6.0"),
            ]
        )
    }

    static func aDependencyThirdPartyDependency(packageFolder: AbsolutePath) -> ThirdPartyDependency {
        return .sources(
            name: "a-dependency",
            products: [
                .init(
                    name: "ALibrary",
                    targets: ["ALibrary"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "ALibrary",
                    sources: [packageFolder.appending(RelativePath("Sources/ALibrary"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("13.0", .all),
                .macOS("10.15"),
                .watchOS("6.0"),
            ]
        )
    }

    static func anotherDependencyThirdPartyDependency(packageFolder: AbsolutePath) -> ThirdPartyDependency {
        return .sources(
            name: "another-dependency",
            products: [
                .init(
                    name: "AnotherLibrary",
                    targets: ["AnotherLibrary"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "AnotherLibrary",
                    sources: [packageFolder.appending(RelativePath("Sources/AnotherLibrary"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("13.0", .all),
                .macOS("10.15"),
                .watchOS("6.0"),
            ]
        )
    }
}

// MARK: - Alamofire package

extension PackageInfo {
    static var alamofireJSON: String {
        """
        {
          "cLanguageStandard" : null,
          "cxxLanguageStandard" : null,
          "dependencies" : [

          ],
          "name" : "Alamofire",
          "packageKind" : "root",
          "pkgConfig" : null,
          "platforms" : [
            {
              "options" : [

              ],
              "platformName" : "macos",
              "version" : "10.12"
            },
            {
              "options" : [

              ],
              "platformName" : "ios",
              "version" : "10.0"
            },
            {
              "options" : [

              ],
              "platformName" : "tvos",
              "version" : "10.0"
            },
            {
              "options" : [

              ],
              "platformName" : "watchos",
              "version" : "3.0"
            }
          ],
          "products" : [
            {
              "name" : "Alamofire",
              "targets" : [
                "Alamofire"
              ],
              "type" : {
                "library" : [
                  "automatic"
                ]
              }
            }
          ],
          "providers" : null,
          "swiftLanguageVersions" : [
            "5"
          ],
          "targets" : [
            {
              "dependencies" : [

              ],
              "exclude" : [

              ],
              "name" : "Alamofire",
              "path" : "Source",
              "resources" : [

              ],
              "settings" : [
                {
                  "condition" : {
                    "platformNames" : [
                      "ios",
                      "macos",
                      "tvos",
                      "watchos"
                    ]
                  },
                  "name" : "linkedFramework",
                  "tool" : "linker",
                  "value" : [
                    "CFNetwork"
                  ]
                }
              ],
              "type" : "regular"
            },
            {
              "dependencies" : [
                {
                  "byName" : [
                    "Alamofire",
                    null
                  ]
                }
              ],
              "exclude" : [

              ],
              "name" : "AlamofireTests",
              "path" : "Tests",
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

    static var alamofire: PackageInfo {
        return .init(
            products: [
                .init(name: "Alamofire", type: .library(.automatic), targets: ["Alamofire"]),
            ],
            targets: [
                .init(
                    name: "Alamofire",
                    path: "Source",
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [
                        .init(
                            tool: .linker,
                            name: .linkedFramework,
                            condition: .init(
                                platformNames: ["ios", "macos", "tvos", "watchos"],
                                config: nil
                            ),
                            value: ["CFNetwork"]
                        ),
                    ],
                    checksum: nil
                ),
                .init(
                    name: "AlamofireTests",
                    path: "Tests",
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [
                        .byName(name: "Alamofire", condition: nil),
                    ],
                    publicHeadersPath: nil,
                    type: .test,
                    settings: [],
                    checksum: nil
                ),
            ],
            platforms: [
                .init(platformName: "macos", version: "10.12", options: []),
                .init(platformName: "ios", version: "10.0", options: []),
                .init(platformName: "tvos", version: "10.0", options: []),
                .init(platformName: "watchos", version: "3.0", options: []),
            ]
        )
    }

    static func alamofireThirdPartyDependency(packageFolder: AbsolutePath) -> ThirdPartyDependency {
        return .sources(
            name: "Alamofire",
            products: [
                .init(
                    name: "Alamofire",
                    targets: ["Alamofire"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "Alamofire",
                    sources: [packageFolder.appending(RelativePath("Source"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
                .macOS("10.12"),
                .tvOS("10.0"),
                .watchOS("3.0"),
            ]
        )
    }
}

// MARK: - GoogleAppMeasurement package

extension PackageInfo {
    static var googleAppMeasurementJSON: String {
        """
        {
          "cLanguageStandard" : "c99",
          "cxxLanguageStandard" : "gnu++14",
          "dependencies" : [
            {
              "explicitName" : "GoogleUtilities",
              "name" : "GoogleUtilities",
              "productFilter" : null,
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "7.2.1",
                    "upperBound" : "8.0.0"
                  }
                ]
              },
              "url" : "https://github.com/google/GoogleUtilities.git"
            },
            {
              "explicitName" : "nanopb",
              "name" : "nanopb",
              "productFilter" : null,
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "2.30908.0",
                    "upperBound" : "2.30909.0"
                  }
                ]
              },
              "url" : "https://github.com/firebase/nanopb.git"
            }
          ],
          "name" : "GoogleAppMeasurement",
          "packageKind" : "root",
          "pkgConfig" : null,
          "platforms" : [
            {
              "options" : [

              ],
              "platformName" : "ios",
              "version" : "10.0"
            }
          ],
          "products" : [
            {
              "name" : "GoogleAppMeasurement",
              "targets" : [
                "GoogleAppMeasurementTarget"
              ],
              "type" : {
                "library" : [
                  "automatic"
                ]
              }
            },
            {
              "name" : "GoogleAppMeasurementWithoutAdIdSupport",
              "targets" : [
                "GoogleAppMeasurementWithoutAdIdSupportTarget"
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
                  "byName" : [
                    "GoogleAppMeasurement",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULAppDelegateSwizzler",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULMethodSwizzler",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULNSData",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULNetwork",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "nanopb",
                    "nanopb",
                    null
                  ]
                }
              ],
              "exclude" : [

              ],
              "name" : "GoogleAppMeasurementTarget",
              "path" : "GoogleAppMeasurementWrapper",
              "resources" : [

              ],
              "settings" : [
                {
                  "name" : "linkedLibrary",
                  "tool" : "linker",
                  "value" : [
                    "sqlite3"
                  ]
                },
                {
                  "name" : "linkedLibrary",
                  "tool" : "linker",
                  "value" : [
                    "c++"
                  ]
                },
                {
                  "name" : "linkedLibrary",
                  "tool" : "linker",
                  "value" : [
                    "z"
                  ]
                },
                {
                  "name" : "linkedFramework",
                  "tool" : "linker",
                  "value" : [
                    "StoreKit"
                  ]
                }
              ],
              "type" : "regular"
            },
            {
              "checksum" : "0cfe662a03d2ad9a4c2fd276efaf3c21ee1fdc855fa76d5d8c26ccb4a8e83180",
              "dependencies" : [

              ],
              "exclude" : [

              ],
              "name" : "GoogleAppMeasurement",
              "resources" : [

              ],
              "settings" : [

              ],
              "type" : "binary",
              "url" : "https://dl.google.com/firebase/ios/swiftpm/8.0.0/GoogleAppMeasurement.zip"
            },
            {
              "dependencies" : [
                {
                  "byName" : [
                    "GoogleAppMeasurementWithoutAdIdSupport",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULAppDelegateSwizzler",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULMethodSwizzler",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULNSData",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "GULNetwork",
                    "GoogleUtilities",
                    null
                  ]
                },
                {
                  "product" : [
                    "nanopb",
                    "nanopb",
                    null
                  ]
                }
              ],
              "exclude" : [

              ],
              "name" : "GoogleAppMeasurementWithoutAdIdSupportTarget",
              "path" : "GoogleAppMeasurementWithoutAdIdSupportWrapper",
              "resources" : [

              ],
              "settings" : [
                {
                  "name" : "linkedLibrary",
                  "tool" : "linker",
                  "value" : [
                    "sqlite3"
                  ]
                },
                {
                  "name" : "linkedLibrary",
                  "tool" : "linker",
                  "value" : [
                    "c++"
                  ]
                },
                {
                  "name" : "linkedLibrary",
                  "tool" : "linker",
                  "value" : [
                    "z"
                  ]
                },
                {
                  "name" : "linkedFramework",
                  "tool" : "linker",
                  "value" : [
                    "StoreKit"
                  ]
                }
              ],
              "type" : "regular"
            },
            {
              "checksum" : "e367d34b193cc65e4beb441092a28112007de4aa67323a85487067de62710718",
              "dependencies" : [

              ],
              "exclude" : [

              ],
              "name" : "GoogleAppMeasurementWithoutAdIdSupport",
              "resources" : [

              ],
              "settings" : [

              ],
              "type" : "binary",
              "url" : "https://dl.google.com/firebase/ios/swiftpm/8.0.0/GoogleAppMeasurementWithoutAdIdSupport.zip"
            }
          ],
          "toolsVersion" : {
            "_version" : "5.3.0"
          }
        }

        """
    }

    static var googleAppMeasurement: PackageInfo {
        return .init(
            products: [
                .init(
                    name: "GoogleAppMeasurement",
                    type: .library(.automatic),
                    targets: ["GoogleAppMeasurementTarget"]
                ),
                .init(
                    name: "GoogleAppMeasurementWithoutAdIdSupport",
                    type: .library(.automatic),
                    targets: ["GoogleAppMeasurementWithoutAdIdSupportTarget"]
                ),
            ],
            targets: [
                .init(
                    name: "GoogleAppMeasurementTarget",
                    path: "GoogleAppMeasurementWrapper",
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [
                        .byName(name: "GoogleAppMeasurement", condition: nil),
                        .product(name: "GULAppDelegateSwizzler", package: "GoogleUtilities", condition: nil),
                        .product(name: "GULMethodSwizzler", package: "GoogleUtilities", condition: nil),
                        .product(name: "GULNSData", package: "GoogleUtilities", condition: nil),
                        .product(name: "GULNetwork", package: "GoogleUtilities", condition: nil),
                        .product(name: "nanopb", package: "nanopb", condition: nil),
                    ],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [
                        .init(
                            tool: .linker,
                            name: .linkedLibrary,
                            condition: nil,
                            value: ["sqlite3"]
                        ),
                        .init(
                            tool: .linker,
                            name: .linkedLibrary,
                            condition: nil,
                            value: ["c++"]
                        ),
                        .init(
                            tool: .linker,
                            name: .linkedLibrary,
                            condition: nil,
                            value: ["z"]
                        ),
                        .init(
                            tool: .linker,
                            name: .linkedFramework,
                            condition: nil,
                            value: ["StoreKit"]
                        ),
                    ],
                    checksum: nil
                ),
                .init(
                    name: "GoogleAppMeasurement",
                    path: nil,
                    url: "https://dl.google.com/firebase/ios/swiftpm/8.0.0/GoogleAppMeasurement.zip",
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .binary,
                    settings: [],
                    checksum: "0cfe662a03d2ad9a4c2fd276efaf3c21ee1fdc855fa76d5d8c26ccb4a8e83180"
                ),
                .init(
                    name: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                    path: "GoogleAppMeasurementWithoutAdIdSupportWrapper",
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [
                        .byName(name: "GoogleAppMeasurementWithoutAdIdSupport", condition: nil),
                        .product(name: "GULAppDelegateSwizzler", package: "GoogleUtilities", condition: nil),
                        .product(name: "GULMethodSwizzler", package: "GoogleUtilities", condition: nil),
                        .product(name: "GULNSData", package: "GoogleUtilities", condition: nil),
                        .product(name: "GULNetwork", package: "GoogleUtilities", condition: nil),
                        .product(name: "nanopb", package: "nanopb", condition: nil),
                    ],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [
                        .init(
                            tool: .linker,
                            name: .linkedLibrary,
                            condition: nil,
                            value: ["sqlite3"]
                        ),
                        .init(
                            tool: .linker,
                            name: .linkedLibrary,
                            condition: nil,
                            value: ["c++"]
                        ),
                        .init(
                            tool: .linker,
                            name: .linkedLibrary,
                            condition: nil,
                            value: ["z"]
                        ),
                        .init(
                            tool: .linker,
                            name: .linkedFramework,
                            condition: nil,
                            value: ["StoreKit"]
                        ),
                    ],
                    checksum: nil
                ),
                .init(
                    name: "GoogleAppMeasurementWithoutAdIdSupport",
                    path: nil,
                    url: "https://dl.google.com/firebase/ios/swiftpm/8.0.0/GoogleAppMeasurementWithoutAdIdSupport.zip",
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .binary,
                    settings: [],
                    checksum: "e367d34b193cc65e4beb441092a28112007de4aa67323a85487067de62710718"
                ),
            ],
            platforms: [
                .init(platformName: "ios", version: "10.0", options: []),
            ]
        )
    }

    static var googleUtilities: PackageInfo {
        return .init(
            products: [
                .init(name: "GULAppDelegateSwizzler", type: .library(.automatic), targets: ["GULAppDelegateSwizzler"]),
                .init(name: "GULMethodSwizzler", type: .library(.automatic), targets: ["GULMethodSwizzler"]),
                .init(name: "GULNSData", type: .library(.automatic), targets: ["GULNSData"]),
                .init(name: "GULNetwork", type: .library(.automatic), targets: ["GULNetwork"]),
            ],
            targets: [
                .init(
                    name: "GULAppDelegateSwizzler",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
                .init(
                    name: "GULMethodSwizzler",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
                .init(
                    name: "GULNSData",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
                .init(
                    name: "GULNetwork",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
            ],
            platforms: [
                .init(platformName: "ios", version: "10.0", options: []),
            ]
        )
    }

    static var nanopb: PackageInfo {
        return .init(
            products: [
                .init(name: "nanopb", type: .library(.automatic), targets: ["nanopb"]),
            ],
            targets: [
                .init(
                    name: "nanopb",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
            ],
            platforms: [
                .init(platformName: "ios", version: "10.0", options: []),
            ]
        )
    }

    static func googleAppMeasurementThirdPartyDependency(artifactsFolder: AbsolutePath, packageFolder: AbsolutePath) -> ThirdPartyDependency {
        return .sources(
            name: "GoogleAppMeasurement",
            products: [
                .init(
                    name: "GoogleAppMeasurement",
                    targets: ["GoogleAppMeasurementTarget"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GoogleAppMeasurementWithoutAdIdSupport",
                    targets: ["GoogleAppMeasurementWithoutAdIdSupportTarget"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "GoogleAppMeasurementTarget",
                    sources: [packageFolder.appending(RelativePath("GoogleAppMeasurementWrapper"))],
                    resources: [],
                    dependencies: [
                        .xcframework(path: artifactsFolder.appending(component: "GoogleAppMeasurement.xcframework")),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULAppDelegateSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULMethodSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNSData"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNetwork"),
                        .thirdPartyTarget(dependency: "nanopb", product: "nanopb"),
                    ]
                ),
                .init(
                    name: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                    sources: [packageFolder.appending(RelativePath("GoogleAppMeasurementWithoutAdIdSupportWrapper"))],
                    resources: [],
                    dependencies: [
                        .xcframework(path: artifactsFolder.appending(component: "GoogleAppMeasurementWithoutAdIdSupport.xcframework")),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULAppDelegateSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULMethodSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNSData"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNetwork"),
                        .thirdPartyTarget(dependency: "nanopb", product: "nanopb"),
                    ]
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    static func googleUtilitiesThirdPartyDependency(packageFolder: AbsolutePath) -> ThirdPartyDependency {
        return .sources(
            name: "GoogleUtilities",
            products: [
                .init(
                    name: "GULAppDelegateSwizzler",
                    targets: ["GULAppDelegateSwizzler"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GULMethodSwizzler",
                    targets: ["GULMethodSwizzler"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GULNSData",
                    targets: ["GULNSData"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GULNetwork",
                    targets: ["GULNetwork"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "GULAppDelegateSwizzler",
                    sources: [packageFolder.appending(RelativePath("Sources/GULAppDelegateSwizzler"))],
                    resources: [],
                    dependencies: []
                ),
                .init(
                    name: "GULMethodSwizzler",
                    sources: [packageFolder.appending(RelativePath("Sources/GULMethodSwizzler"))],
                    resources: [],
                    dependencies: []
                ),
                .init(
                    name: "GULNSData",
                    sources: [packageFolder.appending(RelativePath("Sources/GULNSData"))],
                    resources: [],
                    dependencies: []
                ),
                .init(
                    name: "GULNetwork",
                    sources: [packageFolder.appending(RelativePath("Sources/GULNetwork"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
            ]
        )
    }

    static func nanopbThirdPartyDependency(packageFolder: AbsolutePath) -> ThirdPartyDependency {
        return .sources(
            name: "nanopb",
            products: [
                .init(
                    name: "nanopb",
                    targets: ["nanopb"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "nanopb",
                    sources: [packageFolder.appending(RelativePath("Sources/nanopb"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
            ]
        )
    }
}
