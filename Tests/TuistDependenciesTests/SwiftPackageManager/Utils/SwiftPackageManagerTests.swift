import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class SwiftPackageManagerTests: TuistUnitTestCase {
    private var subject: SwiftPackageManager!
    
    override func setUp() {
        super.setUp()

        subject = SwiftPackageManager()
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
            "resolve"
        ])
        
        // When
        XCTAssertNoThrow(try subject.resolve(at: path))
    }
    
    func test_generateXcodeProject() throws {
        // Given
        let path = try temporaryPath()
        let outputPath = path.appending(component: "Output")
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "generate-xcodeproj",
            "--output",
            outputPath.pathString
        ])
        
        // When / Then
        XCTAssertNoThrow(try subject.generateXcodeProject(at: path, outputPath: outputPath))
    }
    
    func test_loadPackageInfo() throws {
        // Given
        let path = try temporaryPath()
        
        let command = [
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "dump-package",
        ]
        
        let jsons = swiftPackageDumpPackageJsons()
        
        // When / Then
        try jsons.forEach {
            system.succeedCommand(command, output: $0)
            let got = try subject.loadPackageInfo(at: path)
            XCTAssertCodableEqualToJson(got, $0)
        }
    }
    
    func test_loadDependencies() throws {
        // Given
        let path = try temporaryPath()
        
        let command = [
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "show-dependencies",
            "--format",
            "json"
        ]
        
        let jsons = swiftPackageShowDependenciesJsons()
        
        // When / Then
        try jsons.forEach {
            system.succeedCommand(command, output: $0)
            let got = try subject.loadDependencies(at: path)
            XCTAssertCodableEqualToJson(got, $0)
        }
    }
}

private extension SwiftPackageManagerTests {
    func swiftPackageDumpPackageJsons() -> [String] {
        let moyaPackageInfoJson = #"""
        {
          "cLanguageStandard" : null,
          "cxxLanguageStandard" : null,
          "dependencies" : [
            {
              "name" : "Alamofire",
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "5.0.0",
                    "upperBound" : "6.0.0"
                  }
                ]
              },
              "url" : "https:\/\/github.com\/Alamofire\/Alamofire.git"
            },
            {
              "name" : "ReactiveSwift",
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "6.1.0",
                    "upperBound" : "7.0.0"
                  }
                ]
              },
              "url" : "https:\/\/github.com\/Moya\/ReactiveSwift.git"
            },
            {
              "name" : "RxSwift",
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "5.0.0",
                    "upperBound" : "6.0.0"
                  }
                ]
              },
              "url" : "https:\/\/github.com\/ReactiveX\/RxSwift.git"
            },
            {
              "name" : "Quick",
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "2.0.0",
                    "upperBound" : "3.0.0"
                  }
                ]
              },
              "url" : "https:\/\/github.com\/Quick\/Quick.git"
            },
            {
              "name" : "Nimble",
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "8.0.0",
                    "upperBound" : "9.0.0"
                  }
                ]
              },
              "url" : "https:\/\/github.com\/Quick\/Nimble.git"
            },
            {
              "name" : "OHHTTPStubs",
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "9.0.0",
                    "upperBound" : "10.0.0"
                  }
                ]
              },
              "url" : "https:\/\/github.com\/AliSoftware\/OHHTTPStubs.git"
            },
            {
              "name" : "Rocket",
              "requirement" : {
                "range" : [
                  {
                    "lowerBound" : "1.0.0",
                    "upperBound" : "2.0.0"
                  }
                ]
              },
              "url" : "https:\/\/github.com\/shibapm\/Rocket"
            }
          ],
          "name" : "Moya",
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
              "name" : "Moya",
              "targets" : [
                "Moya"
              ],
              "type" : {
                "library" : [
                  "automatic"
                ]
              }
            },
            {
              "name" : "ReactiveMoya",
              "targets" : [
                "ReactiveMoya"
              ],
              "type" : {
                "library" : [
                  "automatic"
                ]
              }
            },
            {
              "name" : "RxMoya",
              "targets" : [
                "RxMoya"
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
                    "Alamofire",
                    null
                  ]
                }
              ],
              "exclude" : [

              ],
              "name" : "Moya",
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
                    "Moya",
                    null
                  ]
                },
                {
                  "byName" : [
                    "ReactiveSwift",
                    null
                  ]
                }
              ],
              "exclude" : [

              ],
              "name" : "ReactiveMoya",
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
                    "Moya",
                    null
                  ]
                },
                {
                  "byName" : [
                    "RxSwift",
                    null
                  ]
                }
              ],
              "exclude" : [

              ],
              "name" : "RxMoya",
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
                    "Moya",
                    null
                  ]
                },
                {
                  "byName" : [
                    "RxMoya",
                    null
                  ]
                },
                {
                  "byName" : [
                    "ReactiveMoya",
                    null
                  ]
                },
                {
                  "byName" : [
                    "Quick",
                    null
                  ]
                },
                {
                  "byName" : [
                    "Nimble",
                    null
                  ]
                },
                {
                  "byName" : [
                    "OHHTTPStubsSwift",
                    null
                  ]
                }
              ],
              "exclude" : [

              ],
              "name" : "MoyaTests",
              "resources" : [

              ],
              "settings" : [

              ],
              "type" : "test"
            }
          ],
          "toolsVersion" : {
            "_version" : "5.0.0"
          }
        }
        """#
        
        return [
            moyaPackageInfoJson,
        ]
    }
    
    func swiftPackageShowDependenciesJsons() -> [String] {
        let moyaPackageDependencies = #"""
        {
          "name": "Moya",
          "url": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya",
          "version": "unspecified",
          "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya",
          "dependencies": [
            {
              "name": "Alamofire",
              "url": "https://github.com/Alamofire/Alamofire.git",
              "version": "5.0.0",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/Alamofire",
              "dependencies": [

              ]
            },
            {
              "name": "ReactiveSwift",
              "url": "https://github.com/Moya/ReactiveSwift.git",
              "version": "6.1.0",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/ReactiveSwift",
              "dependencies": [

              ]
            },
            {
              "name": "RxSwift",
              "url": "https://github.com/ReactiveX/RxSwift.git",
              "version": "5.0.1",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/RxSwift",
              "dependencies": [

              ]
            },
            {
              "name": "Quick",
              "url": "https://github.com/Quick/Quick.git",
              "version": "2.2.0",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/Quick",
              "dependencies": [
                {
                  "name": "Nimble",
                  "url": "https://github.com/Quick/Nimble.git",
                  "version": "8.0.5",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/Nimble",
                  "dependencies": [
                    {
                      "name": "CwlPreconditionTesting",
                      "url": "https://github.com/mattgallagher/CwlPreconditionTesting.git",
                      "version": "1.2.0",
                      "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/CwlPreconditionTesting",
                      "dependencies": [
                        {
                          "name": "CwlCatchException",
                          "url": "https://github.com/mattgallagher/CwlCatchException.git",
                          "version": "1.2.0",
                          "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/CwlCatchException",
                          "dependencies": [

                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            },
            {
              "name": "Nimble",
              "url": "https://github.com/Quick/Nimble.git",
              "version": "8.0.5",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/Nimble",
              "dependencies": [
                {
                  "name": "CwlPreconditionTesting",
                  "url": "https://github.com/mattgallagher/CwlPreconditionTesting.git",
                  "version": "1.2.0",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/CwlPreconditionTesting",
                  "dependencies": [
                    {
                      "name": "CwlCatchException",
                      "url": "https://github.com/mattgallagher/CwlCatchException.git",
                      "version": "1.2.0",
                      "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/CwlCatchException",
                      "dependencies": [

                      ]
                    }
                  ]
                }
              ]
            },
            {
              "name": "OHHTTPStubs",
              "url": "https://github.com/AliSoftware/OHHTTPStubs.git",
              "version": "9.0.0",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/OHHTTPStubs",
              "dependencies": [

              ]
            },
            {
              "name": "Rocket",
              "url": "https://github.com/shibapm/Rocket",
              "version": "1.0.1",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/Rocket",
              "dependencies": [
                {
                  "name": "Yams",
                  "url": "https://github.com/jpsim/Yams",
                  "version": "2.0.0",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/Yams",
                  "dependencies": [

                  ]
                },
                {
                  "name": "Logger",
                  "url": "https://github.com/shibapm/Logger",
                  "version": "0.2.3",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/Logger",
                  "dependencies": [

                  ]
                },
                {
                  "name": "SwiftShell",
                  "url": "https://github.com/kareman/SwiftShell",
                  "version": "5.0.1",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/SwiftShell",
                  "dependencies": [

                  ]
                },
                {
                  "name": "PackageConfig",
                  "url": "https://github.com/shibapm/PackageConfig.git",
                  "version": "0.12.2",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya/.build/checkouts/PackageConfig",
                  "dependencies": [

                  ]
                }
              ]
            }
          ]
        }
        """#
        
        return [
            moyaPackageDependencies
        ]
    }
}
