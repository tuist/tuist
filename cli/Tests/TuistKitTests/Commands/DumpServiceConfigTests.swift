import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistLoggerTesting
import TuistLogging
import TuistTesting

@testable import TuistKit

struct DumpServiceConfigTests {
    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedLogger())
    func printsTheConfigManifest() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let config = """
        import ProjectDescription

        let config = Config(
            compatibleXcodeVersions: .all,
            fullHandle: "tuist/tuist",
            swiftVersion: nil,
            plugins: [],
            generationOptions: .options(),
            installOptions: .options(
                passthroughSwiftPackageManagerArguments: [
                    "--replace-scm-with-registry"
                ]
            )
        )
        """
        try config.write(
            toFile: temporaryDirectory.appending(component: "Tuist.swift").pathString,
            atomically: true,
            encoding: .utf8
        )
        try await DumpService().run(path: temporaryDirectory.pathString, manifest: .config)
        let expected = """
        {
          "fullHandle": "tuist/tuist",
          "inspectOptions": {
            "redundantDependencies": {
              "ignoreTagsMatching": [

              ]
            }
          },
          "network": {
            "proxy": true
          },
          "project": {
            "tuist": {
              "cacheOptions": {
                "keepSourceTargets": false,
                "profiles": {
                  "defaultProfile": {
                    "onlyExternal": {

                    }
                  },
                  "profileByName": {

                  }
                },
                "storages": [
                  {
                    "local": {

                    }
                  },
                  {
                    "remote": {

                    }
                  }
                ]
              },
              "compatibleXcodeVersions": {
                "all": {

                }
              },
              "generationOptions": {
                "additionalPackageResolutionArguments": [

                ],
                "buildInsightsDisabled": false,
                "coverage": {
                  "enabled": false,
                  "prefixMapping": false
                },
                "defaultSwiftVersion": "5",
                "disablePackageVersionLocking": false,
                "disableSandbox": true,
                "enableCaching": false,
                "enforceExplicitDependencies": false,
                "includeGenerateScheme": true,
                "manifestEnvironment": [

                ],
                "onOutdatedDependencies": "warn",
                "optionalAuthentication": false,
                "projectFormat": "pbxproj",
                "registryEnabled": false,
                "resolveDependenciesWithSystemScm": false,
                "staticSideEffectsWarningTargets": {
                  "all": {

                  }
                },
                "testInsightsDisabled": false,
                "warningsAsErrors": {
                  "none": {

                  }
                }
              },
              "installOptions": {
                "packageManifestEnvironment": {
                  "excludedVariablePatterns": [

                  ],
                  "includedVariablePatterns": [

                  ],
                  "usesAutomaticProviderDefaults": true
                },
                "passthroughSwiftPackageManagerArguments": [
                  "--replace-scm-with-registry"
                ]
              },
              "plugins": [

              ]
            }
          },
          "testInsights": {
            "coverage": {
              "upload": true
            }
          },
          "url": "https://tuist.dev",
          "xcodeCache": {
            "upload": true
          }
        }
        """
        let output = Logger.testingLogHandler.collected[.warning, >=]

        #expect(output.contains(expected))
    }
}
