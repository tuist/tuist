#if os(macOS)
    import Command
    import Foundation
    import Mockable
    import Path
    import Testing
    @testable import Rosalind

    @Suite struct AssetUtilControllerTests {
        private let commandRunner = MockCommandRunning()
        private let subject: AssetUtilController

        private let assetInfoJSON = """
        [
          {
            "Appearances" : {
              "UIAppearanceAny" : 0
            },
            "AssetStorageVersion" : "Xcode 16.0 (16A242d) via AssetCatalogSimulatorAgent",
            "Authoring Tool" : "@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-609  [IIO-2629.0.1.9]",
            "CoreUIVersion" : 916,
            "DumpToolVersion" : 969,
            "Key Format" : [
              "kCRThemeAppearanceName",
              "kCRThemeLocalizationName",
              "kCRThemeScaleName",
              "kCRThemeIdiomName",
              "kCRThemeSubtypeName",
              "kCRThemeDimension2Name",
              "kCRThemeDimension1Name",
              "kCRThemeIdentifierName",
              "kCRThemeElementName",
              "kCRThemePartName"
            ],
            "MainVersion" : "@(#)PROGRAM:CoreUI  PROJECT:CoreUI-916\\n",
            "Platform" : "ios",
            "PlatformVersion" : "17.0.0",
            "SchemaVersion" : 2,
            "StorageVersion" : 17,
            "Thinning With CoreUI Version" : 2147483647,
            "ThinningParameters" : "optimized <idiom 1> <subtype 2556> <scale 3> <gamut 1> <graphics 10> <graphicsfallback (9,8,7,6,5,4,3,2,1,0)> <memory 8> <deployment 11> <hostedIdioms (4)>",
            "Timestamp" : 1758560442
          },
          {
            "AssetType" : "Icon Image",
            "BitsPerComponent" : 8,
            "ColorModel" : "RGB",
            "Colorspace" : "srgb",
            "Compression" : "lzfse",
            "Encoding" : "ARGB",
            "Icon Index" : 5,
            "Idiom" : "phone",
            "Name" : "AppIcon",
            "NameIdentifier" : 6849,
            "Opaque" : true,
            "PixelHeight" : 114,
            "PixelWidth" : 114,
            "RenditionName" : "114.png",
            "Scale" : 2,
            "SHA1Digest" : "2C428DBA40B27BFB34BE8D92568563C224F94E43EB75C16D099378D022947D9F",
            "SizeOnDisk" : 3590
          },
          {
            "AssetType" : "Icon Image",
            "BitsPerComponent" : 8,
            "ColorModel" : "RGB",
            "Colorspace" : "srgb",
            "Compression" : "lzfse",
            "Encoding" : "ARGB",
            "Icon Index" : 1,
            "Idiom" : "phone",
            "Name" : "AppIcon",
            "NameIdentifier" : 6849,
            "Opaque" : true,
            "PixelHeight" : 60,
            "PixelWidth" : 60,
            "RenditionName" : "60.png",
            "Scale" : 3,
            "SHA1Digest" : "90875667E4F22292756509061023DF8DA463AB4C9F7E5C8EFBD1294D5D54146F",
            "SizeOnDisk" : 338
          },
          {
            "AssetType" : "Icon Image",
            "BitsPerComponent" : 8,
            "ColorModel" : "RGB",
            "Colorspace" : "srgb",
            "Compression" : "lzfse",
            "Encoding" : "ARGB",
            "Icon Index" : 2,
            "Idiom" : "phone",
            "Name" : "AppIcon",
            "NameIdentifier" : 6849,
            "Opaque" : true,
            "PixelHeight" : 87,
            "PixelWidth" : 87,
            "RenditionName" : "87.png",
            "Scale" : 3,
            "SHA1Digest" : "AD9861B1E50F976B8CABAECCCF45C963002E8DE161E7A4EDBD5386D68AFB8794",
            "SizeOnDisk" : 334
          },
          {
            "AssetType" : "Icon Image",
            "BitsPerComponent" : 8,
            "ColorModel" : "RGB",
            "Colorspace" : "srgb",
            "Compression" : "lzfse",
            "Encoding" : "ARGB",
            "Icon Index" : 3,
            "Idiom" : "phone",
            "Name" : "AppIcon",
            "NameIdentifier" : 6849,
            "Opaque" : true,
            "PixelHeight" : 120,
            "PixelWidth" : 120,
            "RenditionName" : "120.png",
            "Scale" : 3,
            "SHA1Digest" : "5A181B49205BF7384718ADB041755435085995ED37B338475E02D05AED12EFA1",
            "SizeOnDisk" : 334
          },
          {
            "AssetType" : "Icon Image",
            "BitsPerComponent" : 8,
            "ColorModel" : "RGB",
            "Colorspace" : "srgb",
            "Compression" : "lzfse",
            "Encoding" : "ARGB",
            "Icon Index" : 6,
            "Idiom" : "phone",
            "Name" : "AppIcon",
            "NameIdentifier" : 6849,
            "Opaque" : true,
            "PixelHeight" : 180,
            "PixelWidth" : 180,
            "RenditionName" : "180.png",
            "Scale" : 3,
            "SHA1Digest" : "84D9F533EDADFD6C99A74E09A85B5926CF6EEDEF9800A532BC2DC2AAB4D1308D",
            "SizeOnDisk" : 334
          },
          {
            "AssetType" : "MultiSized Image",
            "Idiom" : "phone",
            "Name" : "AppIcon",
            "NameIdentifier" : 6849,
            "Scale" : 1,
            "SHA1Digest" : "91F8F588A3FCC4CFB2DD2CB7BDC22C8ACC9056A0C06207A72C78C49642F2BDD4",
            "SizeOnDisk" : 284,
            "Sizes" : [
              "20x20 index:1 idiom:phone",
              "29x29 index:2 idiom:phone",
              "40x40 index:3 idiom:phone",
              "57x57 index:5 idiom:phone",
              "60x60 index:6 idiom:phone"
            ]
          },
          {
            "AssetType" : "PackedImage",
            "BitsPerComponent" : 8,
            "ColorModel" : "RGB",
            "Colorspace" : "srgb",
            "Compression" : "lzfse",
            "Encoding" : "ARGB",
            "Idiom" : "phone",
            "Name" : "ZZZZPackedAsset-3.1.0-gamut0",
            "Opaque" : true,
            "PixelHeight" : 272,
            "PixelWidth" : 306,
            "RenditionName" : "ZZZZPackedAsset-3.1.0-gamut0",
            "Scale" : 3,
            "SHA1Digest" : "A4AFC948CED333BC481CFACF191F6817EADB607AA5731879BC6B238BC2116090",
            "SizeOnDisk" : 9764
          },
          {
            "AssetType" : "PackedImage",
            "BitsPerComponent" : 8,
            "ColorModel" : "RGB",
            "Colorspace" : "srgb",
            "Compression" : "lzfse",
            "Dimension1" : 1,
            "Encoding" : "ARGB",
            "Idiom" : "phone",
            "Name" : "ZZZZPackedAsset-3.1.0-gamut0",
            "Opaque" : true,
            "PixelHeight" : 64,
            "PixelWidth" : 64,
            "RenditionName" : "ZZZZPackedAsset-3.1.0-gamut0",
            "Scale" : 3,
            "SHA1Digest" : "1E5AB066475B405781D6ECD5E264CCB3F11D268808E74080B719CAD5AA2A11CC",
            "SizeOnDisk" : 1935
          }
        ]
        """

        init() {
            subject = AssetUtilController(commandRunner: commandRunner)
        }

        @Test func info_returnsAssetInfo_whenCommandSucceeds() async throws {
            let path = try AbsolutePath(validating: "/path/to/asset.car")

            given(commandRunner)
                .run(
                    arguments: .value(["/usr/bin/xcrun", "assetutil", "--info", path.pathString]),
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.yield(CommandEvent.standardOutput(Array(assetInfoJSON.utf8)))
                        continuation.finish()
                    }
                )

            let result = try await subject.info(at: path)

            #expect(result.count == 9)

            #expect(result[1].sizeOnDisk == 3590)
            #expect(result[1].sha1Digest == "2C428DBA40B27BFB34BE8D92568563C224F94E43EB75C16D099378D022947D9F")
            #expect(result[1].renditionName == "114.png")

            #expect(result[2].sizeOnDisk == 338)
            #expect(result[2].sha1Digest == "90875667E4F22292756509061023DF8DA463AB4C9F7E5C8EFBD1294D5D54146F")
            #expect(result[2].renditionName == "60.png")
        }

        @Test func info_handlesWarningsBeforeJSON() async throws {
            let path = try AbsolutePath(validating: "/path/to/asset.car")
            let outputWithWarnings = """
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconComposer_Assets/Gradient-3'
            carutil: couldn't materialize rendition 'IconComposer_Assets/Gradient-3' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconComposer_Assets/Gradient-1'
            carutil: couldn't materialize rendition 'IconComposer_Assets/Gradient-1' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconComposer_Assets/Gradient-2'
            carutil: couldn't materialize rendition 'IconComposer_Assets/Gradient-2' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconGroup'
            carutil: couldn't materialize rendition 'IconComposer/Group' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconComposer.iconstack'
            carutil: couldn't materialize rendition 'IconComposer' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconGroup'
            carutil: couldn't materialize rendition 'IconComposer/Group' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconComposer.iconstack'
            carutil: couldn't materialize rendition 'IconComposer' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconGroup'
            carutil: couldn't materialize rendition 'IconComposer/Group' skipping
            CoreUI: Expecting a kCSIElementSignature but didn't find it: 'IconComposer.iconstack'
            carutil: couldn't materialize rendition 'IconComposer' skipping
            \(assetInfoJSON)
            """

            given(commandRunner)
                .run(
                    arguments: .value(["/usr/bin/xcrun", "assetutil", "--info", path.pathString]),
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.yield(CommandEvent.standardOutput(Array(outputWithWarnings.utf8)))
                        continuation.finish()
                    }
                )

            let result = try await subject.info(at: path)

            #expect(result.count == 9)

            #expect(result[1].sizeOnDisk == 3590)
            #expect(result[1].sha1Digest == "2C428DBA40B27BFB34BE8D92568563C224F94E43EB75C16D099378D022947D9F")
            #expect(result[1].renditionName == "114.png")

            #expect(result[2].sizeOnDisk == 338)
            #expect(result[2].sha1Digest == "90875667E4F22292756509061023DF8DA463AB4C9F7E5C8EFBD1294D5D54146F")
            #expect(result[2].renditionName == "60.png")
        }

        @Test func info_throwsParsingError_whenOutputIsInvalid() async throws {
            let path = try AbsolutePath(validating: "/path/to/asset.car")
            let invalidOutput = "Invalid JSON output"

            given(commandRunner)
                .run(
                    arguments: .value(["/usr/bin/xcrun", "assetutil", "--info", path.pathString]),
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.yield(CommandEvent.standardOutput(Array(invalidOutput.utf8)))
                        continuation.finish()
                    }
                )

            await #expect {
                try await subject.info(at: path)
            } throws: { error in
                if let assetError = error as? AssetUtilControllerError,
                   case let .parsingFailed(errorPath) = assetError
                {
                    return errorPath == path
                }
                return false
            }
        }

        @Test func info_throwsDecodingError_whenJSONIsInvalid() async throws {
            let path = try AbsolutePath(validating: "/path/to/asset.car")
            let invalidJSON = "[{\"invalid\": json}]"

            given(commandRunner)
                .run(
                    arguments: .value(["/usr/bin/xcrun", "assetutil", "--info", path.pathString]),
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.yield(CommandEvent.standardOutput(Array(invalidJSON.utf8)))
                        continuation.finish()
                    }
                )

            await #expect {
                try await subject.info(at: path)
            } throws: { error in
                if let assetError = error as? AssetUtilControllerError,
                   case let .decodingFailed(errorPath, jsonString, underlyingError) = assetError
                {
                    return errorPath == path &&
                        jsonString == invalidJSON &&
                        underlyingError is DecodingError
                }
                return false
            }
        }

        @Test func info_throwsError_whenCommandFails() async throws {
            let path = try AbsolutePath(validating: "/path/to/asset.car")
            let expectedError = CommandError.terminated(1, stderr: "Command failed", command: [])

            given(commandRunner)
                .run(
                    arguments: .value(["/usr/bin/xcrun", "assetutil", "--info", path.pathString]),
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.finish(throwing: expectedError)
                    }
                )

            await #expect {
                try await subject.info(at: path)
            } throws: { error in
                if let commandError = error as? CommandError,
                   case let .terminated(code, stderr, _) = commandError
                {
                    return code == 1 && stderr == "Command failed"
                }
                return false
            }
        }

        /// With pool capacity 1, a leaked lock after the first failure would block the second `info` forever on `acquire`.
        @Test func info_returnsAssetInfoForSecondPath_afterFirstPathCommandFails_whenPoolCapacityIsOne() async throws {
            let failingPath = try AbsolutePath(validating: "/path/to/failing.asset.car")
            let okPath = try AbsolutePath(validating: "/path/to/ok.asset.car")
            let commandError = CommandError.terminated(1, stderr: "Command failed", command: [])
            let isolatedLock = PoolLock(capacity: 1)

            try await AssetUtilController.$poolLock.withValue(isolatedLock) {
                given(commandRunner)
                    .run(
                        arguments: .value(["/usr/bin/xcrun", "assetutil", "--info", failingPath.pathString]),
                        environment: .any,
                        workingDirectory: .any
                    )
                    .willReturn(
                        AsyncThrowingStream { continuation in
                            continuation.finish(throwing: commandError)
                        }
                    )

                given(commandRunner)
                    .run(
                        arguments: .value(["/usr/bin/xcrun", "assetutil", "--info", okPath.pathString]),
                        environment: .any,
                        workingDirectory: .any
                    )
                    .willReturn(
                        AsyncThrowingStream { continuation in
                            continuation.yield(CommandEvent.standardOutput(Array(assetInfoJSON.utf8)))
                            continuation.finish()
                        }
                    )

                await #expect {
                    try await subject.info(at: failingPath)
                } throws: { error in
                    if let commandError = error as? CommandError,
                       case let .terminated(code, stderr, _) = commandError
                    {
                        return code == 1 && stderr == "Command failed"
                    }
                    return false
                }

                let result = try await subject.info(at: okPath)

                #expect(result.count == 9)
                #expect(result[1].sizeOnDisk == 3590)
                #expect(result[1].sha1Digest == "2C428DBA40B27BFB34BE8D92568563C224F94E43EB75C16D099378D022947D9F")
                #expect(result[1].renditionName == "114.png")
            }
        }
    }
#endif
