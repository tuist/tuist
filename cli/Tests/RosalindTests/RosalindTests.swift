import FileSystem
import Foundation
import Mockable
import Path
import Testing

@testable import Rosalind

struct RosalindTests {
    private let fileSystem = FileSystem()
    private let appBundleLoader = MockAppBundleLoading()
    private let shasumCalculator = MockShasumCalculating()
    private let androidBundleMetadataService = MockAndroidBundleMetadataServicing()
    /// The stream analyzer has no external dependencies (it inflates ZIP entries via
    /// ZIPFoundation and hashes bytes with swift-crypto), so tests exercise the real
    /// implementation against fixture ZIPs built at runtime with `zipFileOrDirectoryContent`.
    private let androidBundleStreamAnalyzer: AndroidBundleStreamAnalyzing = AndroidBundleStreamAnalyzer()
    #if os(macOS)
        private let assetUtilController = MockAssetUtilControlling()
    #endif
    private let subject: Rosalind

    #if os(macOS)
        init() {
            given(shasumCalculator)
                .calculate(filePath: .any)
                .willProduce { $0.basename }
            given(shasumCalculator)
                .calculate(childrenShasums: .any)
                .willProduce { $0.joined(separator: "-") }
            subject = Rosalind(
                fileSystem: fileSystem,
                appBundleLoader: appBundleLoader,
                shasumCalculator: shasumCalculator,
                androidBundleMetadataService: androidBundleMetadataService,
                androidBundleStreamAnalyzer: androidBundleStreamAnalyzer,
                assetUtilController: assetUtilController
            )
        }
    #else
        init() {
            given(shasumCalculator)
                .calculate(filePath: .any)
                .willProduce { $0.basename }
            given(shasumCalculator)
                .calculate(childrenShasums: .any)
                .willProduce { $0.joined(separator: "-") }
            subject = Rosalind(
                fileSystem: fileSystem,
                appBundleLoader: appBundleLoader,
                shasumCalculator: shasumCalculator,
                androidBundleMetadataService: androidBundleMetadataService,
                androidBundleStreamAnalyzer: androidBundleStreamAnalyzer
            )
        }
    #endif

    @Test func appBundleDoesNotExist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let appBundlePath = temporaryDirectory.appending(component: "App.app")
            // When / Then
            await #expect(
                throws: RosalindError.notFound(appBundlePath)
            ) {
                try await subject.analyzeAppBundle(at: appBundlePath)
            }
        }
    }

    @Test func appBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let appBundlePath = temporaryDirectory.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)
            try await fileSystem.writeText("font-binary", at: appBundlePath.appending(component: "Font.ttf"))
            given(appBundleLoader)
                .load(.any)
                .willReturn(
                    .test(
                        infoPlist: .test(
                            name: "App",
                            bundleId: "com.App",
                            supportedPlatforms: ["iPhoneOS"]
                        )
                    )
                )
            try await fileSystem.makeDirectory(at: appBundlePath.appending(component: "en.lproj"))
            try await fileSystem.writeText("app = App;", at: appBundlePath.appending(components: "en.lproj", "App.strings"))

            // When
            let got = try await subject.analyzeAppBundle(at: appBundlePath)

            // Then
            #expect(
                got == AppBundleReport(
                    bundleId: "com.App",
                    name: "App",
                    type: .app,
                    installSize: 21,
                    downloadSize: nil,
                    platforms: ["iPhoneOS"],
                    version: "1.0",
                    artifacts: [
                        AppBundleArtifact(
                            artifactType: .font,
                            path: "App.app/Font.ttf",
                            size: 11,
                            shasum: "Font.ttf",
                            children: nil
                        ),
                        AppBundleArtifact(
                            artifactType: .directory,
                            path: "App.app/en.lproj",
                            size: 10,
                            shasum: "App.strings",
                            children: [
                                AppBundleArtifact(
                                    artifactType: .localization,
                                    path: "App.app/en.lproj/App.strings",
                                    size: 10,
                                    shasum: "App.strings",
                                    children: nil
                                ),
                            ]
                        ),
                    ]
                )
            )
        }
    }

    @Test func appInXCArchiveDoesNotExist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let xcarchivePath = temporaryDirectory.appending(component: "App.xcarchive")
            try await fileSystem.makeDirectory(at: xcarchivePath)
            // When / Then
            await #expect(
                throws: RosalindError.appNotFound(xcarchivePath)
            ) {
                try await subject.analyzeAppBundle(at: xcarchivePath)
            }
        }
    }

    @Test func appInIPADoesNotExist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "Payload"))
            let ipaPath = temporaryDirectory.appending(component: "App.ipa")
            try await fileSystem.zipFileOrDirectoryContent(at: temporaryDirectory.appending(component: "Payload"), to: ipaPath)
            // When / Then
            await #expect(
                throws: RosalindError.appNotFound(ipaPath)
            ) {
                try await subject.analyzeAppBundle(at: ipaPath)
            }
        }
    }

    @Test func appBundleNotSupported() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let dmgPath = temporaryDirectory.appending(component: "App.dmg")
            try await fileSystem.makeDirectory(at: dmgPath)
            // When / Then
            await #expect(
                throws: RosalindError.notSupported(dmgPath)
            ) {
                try await subject.analyzeAppBundle(at: dmgPath)
            }
        }
    }

    @Test func xcarchiveBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let xcarchivePath = temporaryDirectory.appending(component: "App.xcarchive")
            let appBundlePath = xcarchivePath.appending(components: "Products", "Applications", "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)
            try await fileSystem.writeText("binary-content", at: appBundlePath.appending(component: "App"))
            try await fileSystem.writeText("config-content", at: appBundlePath.appending(component: "Info.plist"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(
                    .test(
                        infoPlist: .test(
                            name: "App",
                            bundleId: "com.App",
                            supportedPlatforms: ["iPhoneOS"]
                        )
                    )
                )

            // When
            let got = try await subject.analyzeAppBundle(at: xcarchivePath)

            // Then
            #expect(
                got == AppBundleReport(
                    bundleId: "com.App",
                    name: "App",
                    type: .xcarchive,
                    installSize: 28,
                    downloadSize: nil,
                    platforms: ["iPhoneOS"],
                    version: "1.0",
                    artifacts: [
                        AppBundleArtifact(
                            artifactType: .file,
                            path: "App.app/App",
                            size: 14,
                            shasum: "App",
                            children: nil
                        ),
                        AppBundleArtifact(
                            artifactType: .file,
                            path: "App.app/Info.plist",
                            size: 14,
                            shasum: "Info.plist",
                            children: nil
                        ),
                    ]
                )
            )
            #expect(got.downloadSize == nil)
        }
    }

    @Test func ipaBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let payloadPath = temporaryDirectory.appending(component: "ipa-contents").appending(component: "Payload")
            let appBundlePath = payloadPath.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)
            try await fileSystem.writeText("binary-content", at: appBundlePath.appending(component: "App"))
            try await fileSystem.writeText("font-binary", at: appBundlePath.appending(component: "Font.ttf"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(
                    .test(
                        infoPlist: .test(
                            name: "App",
                            bundleId: "com.App",
                            supportedPlatforms: ["iPhoneOS"]
                        )
                    )
                )

            // Create IPA file
            let ipaPath = temporaryDirectory.appending(component: "App.ipa")
            try await fileSystem.zipFileOrDirectoryContent(
                at: temporaryDirectory.appending(component: "ipa-contents"),
                to: ipaPath
            )

            // When
            let got = try await subject.analyzeAppBundle(at: ipaPath)

            // Then
            #expect(
                got == AppBundleReport(
                    bundleId: "com.App",
                    name: "App",
                    type: .ipa,
                    installSize: 25,
                    downloadSize: got.downloadSize,
                    platforms: ["iPhoneOS"],
                    version: "1.0",
                    artifacts: [
                        AppBundleArtifact(
                            artifactType: .file,
                            path: "App.app/App",
                            size: 14,
                            shasum: "App",
                            children: nil
                        ),
                        AppBundleArtifact(
                            artifactType: .font,
                            path: "App.app/Font.ttf",
                            size: 11,
                            shasum: "Font.ttf",
                            children: nil
                        ),
                    ]
                )
            )
        }
    }

    @Test func aabBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given: a real AAB-shaped ZIP whose `base/` subtree includes entries a device does
            // download (dex, arm64-v8a libs, xxhdpi drawables, en values) and entries a Play
            // Store split for the reference device would strip (other ABIs, other densities,
            // other locales). The streaming analyzer walks the archive directly, so tests
            // build a real ZIP rather than a stub tree on disk.
            let aabContentsPath = temporaryDirectory.appending(component: "aab-contents")

            let keptDex = "dex-bytecode"
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "dex"))
            try await fileSystem.writeText(
                keptDex,
                at: aabContentsPath.appending(components: "base", "dex", "classes.dex")
            )

            let keptArsc = "resources"
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "res"))
            try await fileSystem.writeText(
                keptArsc,
                at: aabContentsPath.appending(components: "base", "res", "resources.arsc")
            )

            let keptLib = "native-lib"
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "lib", "arm64-v8a"))
            try await fileSystem.writeText(
                keptLib,
                at: aabContentsPath.appending(components: "base", "lib", "arm64-v8a", "libapp.so")
            )

            let keptDrawable = "keeper-icon"
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "res", "drawable-xxhdpi"))
            try await fileSystem.writeText(
                keptDrawable,
                at: aabContentsPath.appending(components: "base", "res", "drawable-xxhdpi", "ic_keep.png")
            )

            let keptValues = "keep-string"
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "res", "values-en"))
            try await fileSystem.writeText(
                keptValues,
                at: aabContentsPath.appending(components: "base", "res", "values-en", "strings.xml")
            )

            // Reference-device filter drops these: a different ABI, a different density bucket,
            // and a different locale. If any of them survived we'd count them in the reported
            // sizes, which is the whole regression Ramon flagged on canary.6.
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "lib", "x86_64"))
            try await fileSystem.writeText(
                "unused-x86_64-lib",
                at: aabContentsPath.appending(components: "base", "lib", "x86_64", "libapp.so")
            )

            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "res", "drawable-mdpi"))
            try await fileSystem.writeText(
                "unused-mdpi-icon",
                at: aabContentsPath.appending(components: "base", "res", "drawable-mdpi", "ic_drop.png")
            )

            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "res", "values-fr"))
            try await fileSystem.writeText(
                "unused-fr-string",
                at: aabContentsPath.appending(components: "base", "res", "values-fr", "strings.xml")
            )

            // These AAB-only protobuf metadata files never reach a device. bundletool converts
            // `resources.pb` into a filtered `resources.arsc`, `manifest/AndroidManifest.xml`
            // into a binary XML file per split, and drops `native.pb`/`assets.pb` entirely.
            // Rosalind can't regenerate the device-format equivalents without a JVM, so it
            // simply skips these so the size numbers don't overshoot bundletool by ~6 MB of
            // protobuf that never ships.
            try await fileSystem.writeText(
                "protobuf-resources",
                at: aabContentsPath.appending(components: "base", "resources.pb")
            )
            try await fileSystem.writeText(
                "protobuf-native",
                at: aabContentsPath.appending(components: "base", "native.pb")
            )
            try await fileSystem.writeText(
                "protobuf-assets",
                at: aabContentsPath.appending(components: "base", "assets.pb")
            )
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "manifest"))
            try await fileSystem.writeText(
                "protobuf-manifest",
                at: aabContentsPath.appending(components: "base", "manifest", "AndroidManifest.xml")
            )

            // Non-`base/` entries mimic packaging metadata that must be excluded from the report.
            try await fileSystem.writeText(
                "packaging-metadata",
                at: aabContentsPath.appending(components: "BundleConfig.pb")
            )

            let aabPath = temporaryDirectory.appending(component: "app.aab")
            try await fileSystem.zipFileOrDirectoryContent(at: aabContentsPath, to: aabPath)

            given(androidBundleMetadataService)
                .aabMetadata(at: .any)
                .willReturn(AndroidBundleMetadata(
                    packageName: "com.test.app",
                    versionName: "2.0",
                    appName: "Test App"
                ))

            // When
            let got = try await subject.analyzeAppBundle(at: aabPath)

            // Then
            #expect(got.bundleId == "com.test.app")
            #expect(got.name == "Test App")
            #expect(got.type == .aab)
            #expect(got.version == "2.0")
            #expect(got.platforms == ["android"])

            // installSize is the decompressed byte total of the entries the reference device
            // installs. Filtered-out ABIs, densities, and locales must not contribute.
            let expectedInstallSize = [keptDex, keptArsc, keptLib, keptDrawable, keptValues]
                .map(\.utf8.count)
                .reduce(0, +)
            #expect(got.installSize == expectedInstallSize)

            // downloadSize is the compressed-byte total of the same kept entries, so it is
            // strictly less than the compressed AAB on disk (which also carries the dropped
            // splits plus packaging metadata).
            #expect(got.downloadSize != nil)
            if let downloadSize = got.downloadSize {
                let aabFileSize = try await Int(fileSystem.fileSizeInBytes(at: aabPath) ?? 0)
                #expect(downloadSize < aabFileSize)
                #expect(downloadSize > 0)
            }

            // The tree is rooted at the package name, and the `base/` prefix is stripped so the
            // report doesn't leak the AAB packaging shape. Filtered-out directories don't show up.
            let artifactPaths = got.artifacts.map(\.path)
            #expect(artifactPaths.sorted() == ["com.test.app/dex", "com.test.app/lib", "com.test.app/res"])

            let libArtifact = got.artifacts.first(where: { $0.path == "com.test.app/lib" })
            #expect(libArtifact?.children?.map(\.path) == ["com.test.app/lib/arm64-v8a"])

            let resArtifact = got.artifacts.first(where: { $0.path == "com.test.app/res" })
            #expect(
                resArtifact?.children?.map(\.path).sorted() == [
                    "com.test.app/res/drawable-xxhdpi",
                    "com.test.app/res/resources.arsc",
                    "com.test.app/res/values-en",
                ]
            )

            let dexArtifact = got.artifacts
                .first(where: { $0.path == "com.test.app/dex" })?
                .children?
                .first(where: { $0.path == "com.test.app/dex/classes.dex" })
            #expect(dexArtifact?.artifactType == .binary)

            let arscArtifact = resArtifact?
                .children?
                .first(where: { $0.path == "com.test.app/res/resources.arsc" })
            #expect(arscArtifact?.artifactType == .asset)

            // Nothing under `BundleConfig.pb` (non-base entry) should show up in the report.
            #expect(!artifactPaths.contains(where: { $0.contains("BundleConfig") }))
        }
    }

    @Test func apkBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let apkContentsPath = temporaryDirectory.appending(component: "apk-contents")
            try await fileSystem.makeDirectory(at: apkContentsPath)
            try await fileSystem.writeText("dex-bytecode", at: apkContentsPath.appending(component: "classes.dex"))
            try await fileSystem.writeText("resources", at: apkContentsPath.appending(component: "resources.arsc"))

            let apkPath = temporaryDirectory.appending(component: "app.apk")
            try await fileSystem.zipFileOrDirectoryContent(at: apkContentsPath, to: apkPath)

            given(androidBundleMetadataService)
                .apkMetadata(at: .any)
                .willReturn(AndroidBundleMetadata(
                    packageName: "com.test.app",
                    versionName: "1.0",
                    appName: "Test App"
                ))

            // When
            let got = try await subject.analyzeAppBundle(at: apkPath)

            // Then
            #expect(got.bundleId == "com.test.app")
            #expect(got.name == "Test App")
            #expect(got.type == .apk)
            #expect(got.version == "1.0")
            #expect(got.platforms == ["android"])
            #expect(got.downloadSize != nil)

            let arscArtifact = got.artifacts
                .first(where: { $0.path.hasSuffix("resources.arsc") })
            #expect(arscArtifact?.artifactType == .asset)
        }
    }
}
