import ArgumentParser
import FileSystem
import Foundation
import Path
import TuistEnvKey

#if os(macOS)
    import XcodeGraph
#endif

public struct InspectBundleCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bundle",
            abstract: "Inspects an app bundle. The app bundle has to be either `.app`, `.xcarchive`, `.ipa`, `.aab`, or `.apk`."
        )
    }

    @Argument(
        help: "The path to the bundle, or the name of an app for Apple platforms to resolve from Xcode build products.",
        completion: .directory,
        envKey: .inspectBundle
    )
    var bundle: String

    #if os(macOS)
        @Option(
            name: [.long, .customShort("C")],
            help: "The configuration of the app to inspect.",
            envKey: .inspectBundleConfiguration
        )
        var configuration: String?

        @Option(
            help: "The platforms (iOS, tvOS, visionOS, watchOS or macOS) to inspect the app for.",
            completion: .list(["iOS", "tvOS", "macOS", "visionOS", "watchOS"]),
            envKey: .inspectBundlePlatform
        )
        var platforms: [XcodeGraph.Platform] = []

        @Option(
            help: "The derived data path to find the app in. When absent, the system-configured one.",
            completion: .directory,
            envKey: .inspectBundleDerivedDataPath
        )
        var derivedDataPath: String?
    #endif

    @Flag(
        help: "The output in JSON format.",
        envKey: .inspectBundleJSON
    )
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project associated with the inspected bundle.",
        completion: .directory,
        envKey: .inspectBundlePath
    )
    var path: String?

    public func run() async throws {
        #if os(macOS)
            try await InspectBundleCommandService()
                .run(
                    path: path,
                    bundle: bundle,
                    configuration: configuration,
                    platforms: platforms,
                    derivedDataPath: derivedDataPath,
                    json: json
                )
        #else
            try await InspectBundleCommandService()
                .run(
                    path: path,
                    bundle: bundle,
                    json: json
                )
        #endif
    }
}
