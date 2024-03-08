import CryptoKit
import Darwin
import Foundation
import Mockable
import TSCBasic

public protocol Environmenting: Actor {
    var shouldOutputBeColoured: Bool { get }
    var tuistVariables: [String: String] { get }
    var tuistConfigVariables: [String: String] { get }
    var manifestLoadingVariables: [String: String] { get }
    var isVerbose: Bool { get }
    var isCI: Bool { get }
    var cacheDirectory: AbsolutePath { get }
    var uniqueHostId: String { get }
    var macOSVersion: String { get }
    var swiftVersion: String { get }
    var hardwareName: String { get }
    var githubAPIToken: String? { get }
    var useManifestsCache: Bool { get }
    var detailedLog: Bool { get }
    var osLog: Bool { get }
}

#if MOCKING
    public actor MockEnvironment: Environmenting {
        public var shouldOutputBeColoured: Bool = false
        public var isCI: Bool = false
        public var isStandardOutputInteractive: Bool = false
        public var isVerbose: Bool = false
        public var cacheDirectory: AbsolutePath = .root
        public var tuistVariables: [String: String] = [:]
        public var tuistConfigVariables: [String: String] = [:]
        public var manifestLoadingVariables: [String: String] = [:]
        public var uniqueHostId: String = "host"
        public var macOSVersion: String = "14.2.1"
        public var swiftVersion: String = "5.9"
        public var hardwareName: String = "macbook"
        public var githubAPIToken: String?
        public var useManifestsCache: Bool = true
        public var detailedLog: Bool = false
        public var osLog: Bool = false
    }
#endif

public actor Environment: Environmenting {
    // MARK: - Attributes

    @available(*, deprecated, message: "Use the instance passed from the command")
    public static let shared: Environmenting = try! Environment()

    public let shouldOutputBeColoured: Bool
    public let isCI: Bool
    public let isStandardOutputInteractive: Bool
    public let isVerbose: Bool
    public let cacheDirectory: AbsolutePath
    public let tuistVariables: [String: String]
    public let tuistConfigVariables: [String: String]
    public let manifestLoadingVariables: [String: String]
    public let uniqueHostId: String
    public let macOSVersion: String
    public let swiftVersion: String
    public let hardwareName: String
    public let githubAPIToken: String?
    public let useManifestsCache: Bool
    public let detailedLog: Bool
    public let osLog: Bool

    public init(env: [String: String] = ProcessInfo.processInfo.environment) throws {
        self.init(
            shouldOutputBeColoured: try Environment.shouldOutputBeColoured(from: env),
            isCI: try Environment.isCI(from: env),
            isStandardOutputInteractive: try Environment.isStandardOutputInteractive(from: env),
            isVerbose: try Environment.isVerbose(from: env),
            cacheDirectory: try Environment.cacheDirectory(from: env),
            tuistVariables: try Environment.tuistVariables(from: env),
            tuistConfigVariables: try Environment.tuistConfigVariables(from: env),
            manifestLoadingVariables: try Environment.manifestLoadingVariables(from: env),
            uniqueHostId: try Environment.uniqueHostId(),
            macOSVersion: Environment.macOSVersion(),
            swiftVersion: try Environment.swiftVersion(),
            hardwareName: Environment.hardwareName(),
            githubAPIToken: Environment.githubAPIToken(from: env),
            useManifestsCache: Environment.useManifestsCache(from: env),
            detailedLog: Environment.detailedLog(from: env),
            osLog: Environment.osLog(from: env)
        )
    }

    public init(
        shouldOutputBeColoured: Bool,
        isCI: Bool,
        isStandardOutputInteractive: Bool,
        isVerbose: Bool,
        cacheDirectory: AbsolutePath,
        tuistVariables: [String: String],
        tuistConfigVariables: [String: String],
        manifestLoadingVariables: [String: String],
        uniqueHostId: String,
        macOSVersion: String,
        swiftVersion: String,
        hardwareName: String,
        githubAPIToken: String?,
        useManifestsCache: Bool,
        detailedLog: Bool,
        osLog: Bool
    ) {
        self.shouldOutputBeColoured = shouldOutputBeColoured
        self.isCI = isCI
        self.isStandardOutputInteractive = isStandardOutputInteractive
        self.isVerbose = isVerbose
        self.cacheDirectory = cacheDirectory
        self.tuistVariables = tuistVariables
        self.tuistConfigVariables = tuistConfigVariables
        self.manifestLoadingVariables = manifestLoadingVariables
        self.uniqueHostId = uniqueHostId
        self.macOSVersion = macOSVersion
        self.swiftVersion = swiftVersion
        self.hardwareName = hardwareName
        self.githubAPIToken = githubAPIToken
        self.useManifestsCache = useManifestsCache
        self.detailedLog = detailedLog
        self.osLog = osLog
    }

    private static func shouldOutputBeColoured(from env: [String: String]) throws -> Bool {
        let noColor = if let noColorEnvVariable = env["NO_COLOR"] {
            Constants.trueValues.contains(noColorEnvVariable)
        } else {
            false
        }
        let ciColorForce = if let ciColorForceEnvVariable = env["CLICOLOR_FORCE"] {
            Constants.trueValues.contains(ciColorForceEnvVariable)
        } else {
            false
        }
        if noColor {
            return false
        } else if ciColorForce {
            return true
        } else {
            let isPiped = isatty(fileno(stdout)) == 0
            return !isPiped
        }
    }

    private static func isCI(from env: [String: String]) throws -> Bool {
        let variables = [
            // GitHub: https://help.github.com/en/actions/automating-your-workflow-with-github-actions/using-environment-variables
            "GITHUB_RUN_ID",
            // CircleCI: https://circleci.com/docs/2.0/env-vars/
            // Bitrise: https://devcenter.bitrise.io/builds/available-environment-variables/
            // Buildkite: https://buildkite.com/docs/pipelines/environment-variables
            // Travis: https://docs.travis-ci.com/user/environment-variables/
            "CI",
            // Jenkins: https://wiki.jenkins.io/display/JENKINS/Building+a+software+project
            "BUILD_NUMBER",
        ]
        return env.first(where: {
            variables.contains($0.key)
        }) != nil
    }

    private static func isStandardOutputInteractive(from env: [String: String]) throws -> Bool {
        let termType = env["TERM"]
        if let t = termType, t.lowercased() != "dumb", isatty(fileno(stdout)) != 0 {
            return true
        }
        return false
    }

    private static func isVerbose(from env: [String: String]) throws -> Bool {
        guard let variable = env["TUIST_CONFIG_VERBOSE"] else { return false }
        return Constants.trueValues.contains(variable)
    }

    private static func cacheDirectory(from env: [String: String]) throws -> AbsolutePath {
        if let xdgCacheHome = env["XDG_CACHE_HOME"] {
            return try AbsolutePath(validating: xdgCacheHome)
        } else {
            return FileHandler.shared.homeDirectory.appending(components: ".cache")
        }
    }

    private static func tuistVariables(from env: [String: String]) throws -> [String: String] {
        env.filter { $0.key.hasPrefix("TUIST_") }.filter { !$0.key.hasPrefix("TUIST_CONFIG_") }
    }

    private static func tuistConfigVariables(from env: [String: String]) throws -> [String: String] {
        env.filter { $0.key.hasPrefix("TUIST_CONFIG_") }
    }

    private static func manifestLoadingVariables(from env: [String: String]) throws -> [String: String] {
        let allowedVariableKeys = [
            "DEVELOPER_DIR",
        ]
        let allowedVariables = env.filter {
            allowedVariableKeys.contains($0.key)
        }
        return try tuistVariables(from: env).merging(allowedVariables, uniquingKeysWith: { $1 })
    }

    private static func uniqueHostId() throws -> String {
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        defer { IOObjectRelease(platformExpert) }
        guard platformExpert != 0 else {
            fatalError("Couldn't obtain the platform expert")
        }
        let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ).takeRetainedValue() as! String // swiftlint:disable:this force_cast
        return Insecure.MD5.hash(data: uuid.data(using: .utf8)!)
            .compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func macOSVersion() -> String {
        """
        \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\
        \(ProcessInfo.processInfo.operatingSystemVersion.minorVersion).\
        \(ProcessInfo.processInfo.operatingSystemVersion.patchVersion)
        """
    }

    private static func swiftVersion() throws -> String {
        try System.shared // swiftlint:disable:this force_try
            .capture(["/usr/bin/xcrun", "swift", "-version"])
            .components(separatedBy: "Swift version ").last!
            .components(separatedBy: " ").first!
    }

    private static func hardwareName() -> String {
        var sysinfo = utsname()
        let result = uname(&sysinfo)
        guard result == EXIT_SUCCESS else { fatalError("uname result is \(result)") }
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        return String(bytes: data, encoding: .ascii)!.trimmingCharacters(in: .controlCharacters)
    }

    private static func githubAPIToken(from env: [String: String]) -> String? {
        return env["TUIST_CONFIG_GITHUB_API_TOKEN"] ?? env["GITHUB_API_TOKEN"]
    }

    private static func useManifestsCache(from env: [String: String]) -> Bool {
        guard let variable = env["TUIST_CONFIG_CACHE_MANIFESTS"] else { return false }
        return Constants.trueValues.contains(variable)
    }

    private static func detailedLog(from env: [String: String]) -> Bool {
        guard let variable = env["TUIST_CONFIG_DETAILED_LOG"] else { return false }
        return Constants.trueValues.contains(variable)
    }

    private static func osLog(from env: [String: String]) -> Bool {
        guard let variable = env["TUIST_CONFIG_OS_LOG"] else { return false }
        return Constants.trueValues.contains(variable)
    }
}
