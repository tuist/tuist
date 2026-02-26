import Path
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct XCConfigurationMapperTests {
    let mapper = XCConfigurationMapper()

    @Test("Returns default settings when configuration list is nil")
    func nilConfigurationListReturnsDefault() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        // When
        let settings = try mapper.map(xcodeProj: xcodeProj, configurationList: nil)

        // Then
        #expect(settings == Settings.default)
    }

    @Test("Maps a single build configuration correctly")
    func singleConfigurationMapping() async throws {
        // Given
        let pbxProj = PBXProj()
        let config: XCBuildConfiguration = .testDebug().add(to: pbxProj)
        let configList = XCConfigurationList.test(
            buildConfigurations: [config],
            defaultConfigurationName: "Debug"
        ).add(to: pbxProj)
        let xcodeProj = try await XcodeProj.test(configurationList: configList, pbxProj: pbxProj)

        // When
        let settings = try mapper.map(xcodeProj: xcodeProj, configurationList: configList)

        // Then
        #expect(settings.configurations.count == 1)

        let configKey = try #require(settings.configurations.keys.first)
        #expect(configKey.name == "Debug")
        #expect(configKey.variant == .debug)

        let debugConfig = try #require(settings.configurations[configKey])
        #expect(debugConfig?.settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.debug")
    }

    @Test("Maps multiple build configurations correctly")
    func multipleConfigurations() async throws {
        // Given
        let pbxProj = PBXProj()
        let debugConfiguration: XCBuildConfiguration = .testDebug().add(to: pbxProj)
        let releaseConfiguration: XCBuildConfiguration = .testRelease().add(to: pbxProj)
        let configs = [debugConfiguration, releaseConfiguration]
        let configList = XCConfigurationList.test(buildConfigurations: configs).add(to: pbxProj)
        let xcodeProj = try await XcodeProj.test(configurationList: configList, pbxProj: pbxProj)

        // When
        let settings = try mapper.map(xcodeProj: xcodeProj, configurationList: configList)

        // Then
        #expect(settings.configurations.count == 2)

        let debugKey = try #require(settings.configurations.keys.first { $0.name == "Debug" })
        let releaseKey = try #require(settings.configurations.keys.first { $0.name == "Release" })

        #expect(debugKey.variant == .debug)
        #expect(releaseKey.variant == .release)

        let debugConfig = try #require(settings.configurations[debugKey])
        let releaseConfig = try #require(settings.configurations[releaseKey])

        #expect(debugConfig?.settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.debug")
        #expect(releaseConfig?.settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.release")
    }

    @Test("Resolves XCConfig file paths correctly")
    func xCConfigPathResolution() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj
        let baseConfigRef = try PBXFileReference.test(
            sourceTree: .sourceRoot,
            path: "Config.xcconfig"
        ).add(to: pbxProj)
            .addToMainGroup(in: pbxProj)

        let buildConfig = XCBuildConfiguration.testDebug(
            buildSettings: ["PRODUCT_BUNDLE_IDENTIFIER": "com.example"]
        ).add(to: pbxProj)
        buildConfig.baseConfiguration = baseConfigRef

        let configList = XCConfigurationList(
            buildConfigurations: [buildConfig],
            defaultConfigurationName: "Debug",
            defaultConfigurationIsVisible: false
        )

        // When
        let settings = try mapper.map(xcodeProj: xcodeProj, configurationList: configList)

        // Then
        let debugKey = try #require(settings.configurations.keys.first { $0.name == "Debug" })
        let debugConfig = try #require(settings.configurations[debugKey])

        let expectedPath = "\(xcodeProj.srcPathString)/Config.xcconfig"
        #expect(debugConfig?.xcconfig?.pathString == expectedPath)
    }

    @Test("Maps array values correctly in build settings")
    func arrayValueMapping() async throws {
        // Given
        let pbxProj = PBXProj()
        let config: XCBuildConfiguration = .testDebug(
            buildSettings: ["SOME_ARRAY": ["val1", "val2"]]
        ).add(to: pbxProj)
        let configList = XCConfigurationList.test(buildConfigurations: [config]).add(to: pbxProj)
        let xcodeProj = try await XcodeProj.test(configurationList: configList, pbxProj: pbxProj)

        // When
        let settings = try mapper.map(xcodeProj: xcodeProj, configurationList: configList)

        // Then
        #expect(settings.configurations.count == 1)

        let debugKey = try #require(settings.configurations.keys.first { $0.name == "Debug" })
        let debugConfig = try #require(settings.configurations[debugKey])

        #expect(debugConfig?.settings["SOME_ARRAY"] == ["val1", "val2"])
    }
}
