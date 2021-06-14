import TuistGraph
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

    static var testThirdPartyDependency: ThirdPartyDependency {
        return .sources(
            name: "test",
            products: [
                .init(name: "Tuist", targets: ["Tuist"], libraryType: .static),
            ],
            targets: [],
            minDeploymentTargets: [
                .iOS("13.0", .all),
                .macOS("10.15"),
                .watchOS("6.0"),
            ]
        )
    }

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

    static var alamofireThirdPartyDependency: ThirdPartyDependency {
        return .sources(
            name: "Alamofire",
            products: [
                .init(name: "Alamofire", targets: ["Alamofire"], libraryType: .automatic),
            ],
            targets: [],
            minDeploymentTargets: [
                .iOS("10.0", .all),
                .macOS("10.12"),
                .tvOS("10.0"),
                .watchOS("3.0"),
            ]
        )
    }

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
                .init(name: "GoogleAppMeasurement", type: .library(.automatic), targets: ["GoogleAppMeasurementTarget"]),
                .init(name: "GoogleAppMeasurementWithoutAdIdSupport", type: .library(.automatic), targets: ["GoogleAppMeasurementWithoutAdIdSupportTarget"]),
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

    static var googleAppMeasurementThirdPartyDependency: ThirdPartyDependency {
        return .sources(
            name: "GoogleAppMeasurement",
            products: [
                .init(name: "GoogleAppMeasurement", targets: ["GoogleAppMeasurementTarget"], libraryType: .automatic),
                .init(name: "GoogleAppMeasurementWithoutAdIdSupport", targets: ["GoogleAppMeasurementWithoutAdIdSupportTarget"], libraryType: .automatic),
            ],
            targets: [],
            minDeploymentTargets: [
                .iOS("10.0", .all),
            ]
        )
    }
}
