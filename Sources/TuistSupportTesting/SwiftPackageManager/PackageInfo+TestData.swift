import TSCBasic
import TSCUtility
import TuistGraph
@testable import TuistSupport

// MARK: - Test package

extension PackageInfo {
    public static func test(
        products: [Product] = [],
        targets: [Target] = [],
        platforms: [Platform] = [],
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil,
        swiftLanguageVersions: [TSCUtility.Version]? = nil
    ) -> Self {
        .init(
            products: products,
            targets: targets,
            platforms: platforms,
            cLanguageStandard: cLanguageStandard,
            cxxLanguageStandard: cxxLanguageStandard,
            swiftLanguageVersions: swiftLanguageVersions
        )
    }

    public static var testJSON: String {
        """
        {
          "cLanguageStandard" : "c99",
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
                    {
                      "platformNames" : [
                        "ios"
                      ]
                    }
                  ]
                }
              ],
              "exclude" : [
                "excluded/sources"
              ],
              "name" : "Tuist",
              "path" : "customPath",
              "publicHeadersPath" : "custom/Public/Headers/Path",
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
                  "tool": "c",
                  "name": "headerSearchPath",
                  "value": [
                    "cSearchPath"
                  ]
                },
                {
                  "tool": "cxx",
                  "name": "headerSearchPath",
                  "value": [
                    "cxxSearchPath"
                  ]
                },
                {
                  "tool": "c",
                  "name": "unsafeFlags",
                  "value": [
                    "CUSTOM_C_FLAG"
                  ]
                },
                {
                  "tool": "cxx",
                  "name": "unsafeFlags",
                  "value": [
                    "CUSTOM_CXX_FLAG"
                  ]
                },
                {
                  "tool": "swift",
                  "name": "unsafeFlags",
                  "value": [
                    "CUSTOM_SWIFT_FLAG1",
                    "CUSTOM_SWIFT_FLAG2"
                  ]
                },
                {
                  "tool": "c",
                  "name": "define",
                  "value": [
                    "C_DEFINE=C_VALUE"
                  ]
                },
                {
                  "tool": "cxx",
                  "name": "define",
                  "value": [
                    "CXX_DEFINE=CXX_VALUE"
                  ]
                },
                {
                  "tool": "swift",
                  "name": "define",
                  "value": [
                    "SWIFT_DEFINE"
                  ]
                },
                {
                  "condition" : {
                    "platformNames" : [
                      "watchos"
                    ]
                  },
                  "name" : "linkedFramework",
                  "tool" : "linker",
                  "value" : [
                    "WatchKit"
                  ]
                },
                {
                  "condition" : {
                    "platformNames" : [
                      "tvos"
                    ]
                  },
                  "tool": "swift",
                  "name": "define",
                  "value": [
                    "SWIFT_TVOS_DEFINE"
                  ]
                }
              ],
              "type" : "regular"
            },
            {
              "dependencies" : [
                {
                  "product" : [
                    "AnotherLibrary",
                    "another-dependency",
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
              "dependencies" : [],
              "exclude" : [

              ],
              "name" : "TestUtilities",
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
                },
                {
                  "byName" : [
                    "TestUtilities",
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

    public static var test: PackageInfo {
        .init(
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
                    exclude: [
                        "excluded/sources",
                    ],
                    dependencies: [
                        .target(name: "TuistKit", condition: nil),
                        .product(
                            name: "ALibrary",
                            package: "a-dependency",
                            condition: .init(platformNames: ["ios"], config: nil)
                        ),
                    ],
                    publicHeadersPath: "custom/Public/Headers/Path",
                    type: .regular,
                    settings: [
                        .init(tool: .c, name: .headerSearchPath, condition: nil, value: ["cSearchPath"]),
                        .init(tool: .cxx, name: .headerSearchPath, condition: nil, value: ["cxxSearchPath"]),
                        .init(tool: .c, name: .unsafeFlags, condition: nil, value: ["CUSTOM_C_FLAG"]),
                        .init(tool: .cxx, name: .unsafeFlags, condition: nil, value: ["CUSTOM_CXX_FLAG"]),
                        .init(
                            tool: .swift,
                            name: .unsafeFlags,
                            condition: nil,
                            value: ["CUSTOM_SWIFT_FLAG1", "CUSTOM_SWIFT_FLAG2"]
                        ),
                        .init(tool: .c, name: .define, condition: nil, value: ["C_DEFINE=C_VALUE"]),
                        .init(tool: .cxx, name: .define, condition: nil, value: ["CXX_DEFINE=CXX_VALUE"]),
                        .init(tool: .swift, name: .define, condition: nil, value: ["SWIFT_DEFINE"]),
                        .init(
                            tool: .linker,
                            name: .linkedFramework,
                            condition: .init(platformNames: ["watchos"], config: nil),
                            value: ["WatchKit"]
                        ),
                        .init(
                            tool: .swift,
                            name: .define,
                            condition: .init(platformNames: ["tvos"], config: nil),
                            value: ["SWIFT_TVOS_DEFINE"]
                        ),
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
                        .product(name: "AnotherLibrary", package: "another-dependency", condition: nil),
                    ],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
                .init(
                    name: "TestUtilities",
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
                    name: "TuistKitTests",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [
                        .byName(name: "TuistKit", condition: nil),
                        .byName(name: "TestUtilities", condition: nil),
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
            ],
            cLanguageStandard: "c99",
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
    }

    public static var aDependency: PackageInfo {
        .init(
            products: [
                .init(name: "ALibrary", type: .library(.automatic), targets: ["ALibrary", "ALibraryUtils"]),
            ],
            targets: [
                .init(
                    name: "ALibrary",
                    path: nil,
                    url: nil,
                    sources: nil,
                    resources: [],
                    exclude: [],
                    dependencies: [
                        .byName(name: "ALibraryUtils", condition: nil),
                    ],
                    publicHeadersPath: nil,
                    type: .regular,
                    settings: [],
                    checksum: nil
                ),
                .init(
                    name: "ALibraryUtils",
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
            platforms: [],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
    }

    static var anotherDependency: PackageInfo {
        .init(
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
            ],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
    }
}

// MARK: - Alamofire package

extension PackageInfo {
    public static var alamofireJSON: String {
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

    public static var alamofire: PackageInfo {
        .init(
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
            ],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: ["5.0.0"]
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

    public static var googleAppMeasurement: PackageInfo {
        .init(
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
            ],
            cLanguageStandard: "c99",
            cxxLanguageStandard: "gnu++14",
            swiftLanguageVersions: nil
        )
    }

    public static var googleUtilities: PackageInfo {
        .init(
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
            ],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
    }

    public static var nanopb: PackageInfo {
        .init(
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
            ],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
    }
}
