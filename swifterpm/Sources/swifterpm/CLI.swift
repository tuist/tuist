import ArgumentParser
import Foundation

public let swifterpmVersion = "0.9.0"

struct CLIPath: Equatable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func optional(_ path: String?) -> CLIPath? {
        path.map(CLIPath.init)
    }

    var path: String {
        URL(fileURLWithPath: rawValue).path
    }

    func resolved(relativeTo baseDirectory: URL) -> URL {
        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue).standardizedFileURL
        }
        return baseDirectory
            .appendingPathComponent(rawValue)
            .standardizedFileURL
    }
}

struct CLI {
    var chdir: CLIPath?
    var packagePath: CLIPath?
    var cachePath: CLIPath?
    var scratchPath: CLIPath?
    var buildPath: CLIPath?
    var configPath: CLIPath?
    var securityPath: CLIPath?
    var disableSandbox = false
    var enableDependencyCache = false
    var disableDependencyCache = false
    var skipUpdate = false
    var forceResolvedVersions = false
    var disableAutomaticResolution = false
    var onlyUseVersionsFromResolvedFile = false
    var replaceSCMWithRegistry = false
    var useRegistryIdentityForSCM = false
    var defaultRegistryURL: String?
    var disableSCMToRegistryTransformation = false
    var quiet = false
    var disablePackageInfoCache = false
    var packageInfoCachePath: CLIPath?
    var cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization?
    var command: Command

    enum Command {
        case resolve(ResolveOptions)
        case update(UpdateOptions)
        case restore(RestoreOptions)
    }

    struct ResolveOptions {
        var packageName: String?
        var version: String?
        var branch: String?
        var revision: String?
        var packageDir = CLIPath(".")
        var cacheDir: CLIPath?
        var write = false
        var restore = false
        var printOnly = false
    }

    struct UpdateOptions {
        var packageNames: [String] = []
        var packageDir = CLIPath(".")
        var cacheDir: CLIPath?
        var write = false
        var restore = false
        var printOnly = false
    }

    struct RestoreOptions {
        var packageDir = CLIPath(".")
        var cacheDir: CLIPath?
        var scratchDir: CLIPath?
    }
}

enum CLIAction: String, ExpressibleByArgument {
    case resolve
    case update
    case restore
}

public enum SwifterPMParsedCommand: Sendable {
    case resolve(SwifterPMResolutionRequest)
    case update(SwifterPMResolutionRequest)
    case restore(SwifterPMRestoreRequest)
}

public enum SwifterPMCommandParser {
    public static func parse(_ args: [String]) async throws -> SwifterPMParsedCommand {
        let cli = try CLIParser.parse(args)
        let paths = try await CLIPathResolver(chdir: cli.chdir)

        switch cli.command {
        case .resolve(let options):
            try CLIRunner.ensureWholePackageResolution(
                packageName: options.packageName,
                version: options.version,
                branch: options.branch,
                revision: options.revision
            )
            return .resolve(
                try resolutionRequest(
                    cli: cli,
                    paths: paths,
                    packageDir: options.packageDir,
                    cacheDir: options.cacheDir,
                    write: options.write,
                    restore: options.restore,
                    printOnly: options.printOnly
                )
            )
        case .update(let options):
            if !options.packageNames.isEmpty {
                throw ToolError.message("package-specific update is not supported yet")
            }
            return .update(
                try resolutionRequest(
                    cli: cli,
                    paths: paths,
                    packageDir: options.packageDir,
                    cacheDir: options.cacheDir,
                    write: options.write,
                    restore: options.restore,
                    printOnly: options.printOnly
                )
            )
        case .restore(let options):
            let package = CLIRunner.canonicalPackageDir(
                CLIRunner.commandPackageDir(
                    cli: cli, paths: paths, commandPackageDir: options.packageDir)
            )
            return .restore(
                SwifterPMRestoreRequest(
                    packageDirectory: package,
                    cacheDirectory: CLIRunner.cliCacheDir(
                        cli: cli, paths: paths, commandCacheDir: options.cacheDir),
                    scratchDirectory: CLIRunner.commandScratchDir(
                        cli: cli, paths: paths, packageDir: package, commandScratchDir: options.scratchDir),
                    registryConfigurationPath: paths.resolve(cli.configPath),
                    defaultRegistryURL: cli.defaultRegistryURL,
                    disableSandbox: cli.disableSandbox,
                    disablePackageInfoCache: cli.disablePackageInfoCache,
                    packageInfoCacheDirectory: paths.resolve(cli.packageInfoCachePath),
                    cachedDirectoryMaterialization: cli.cachedDirectoryMaterialization,
                    quiet: cli.quiet
                )
            )
        }
    }

    private static func resolutionRequest(
        cli: CLI,
        paths: CLIPathResolver,
        packageDir: CLIPath,
        cacheDir: CLIPath?,
        write: Bool,
        restore: Bool,
        printOnly: Bool
    ) throws -> SwifterPMResolutionRequest {
        let package = CLIRunner.canonicalPackageDir(
            CLIRunner.commandPackageDir(cli: cli, paths: paths, commandPackageDir: packageDir)
        )
        return SwifterPMResolutionRequest(
            packageDirectory: package,
            cacheDirectory: CLIRunner.cliCacheDir(cli: cli, paths: paths, commandCacheDir: cacheDir),
            scratchDirectory: CLIRunner.commandScratchDir(
                cli: cli, paths: paths, packageDir: package, commandScratchDir: nil),
            registryConfigurationPath: paths.resolve(cli.configPath),
            defaultRegistryURL: cli.defaultRegistryURL,
            disableSandbox: cli.disableSandbox,
            forceResolvedVersions: cli.forceResolvedVersions || cli.disableAutomaticResolution
                || cli.onlyUseVersionsFromResolvedFile,
            skipUpdate: cli.skipUpdate,
            writeResolvedFile: CLIRunner.shouldWrite(write: write, printOnly: printOnly),
            restorePackage: CLIRunner.shouldRestore(restore: restore, printOnly: printOnly),
            disablePackageInfoCache: cli.disablePackageInfoCache,
            packageInfoCacheDirectory: paths.resolve(cli.packageInfoCachePath),
            scmToRegistryTransformation: try CLIRunner.scmToRegistryTransformation(cli),
            cachedDirectoryMaterialization: cli.cachedDirectoryMaterialization,
            quiet: cli.quiet
        )
    }
}

public struct SwifterPMCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swifterpm",
        abstract: "Resolve and restore Swift package dependencies.",
        version: swifterpmVersion
    )

    @Option(name: .customLong("chdir"))
    var chdir: String?

    @Option(name: .customLong("package-path"))
    var packagePath: String?

    @Option(name: .customLong("cache-path"))
    var cachePath: String?

    @Option(name: .customLong("scratch-path"))
    var scratchPath: String?

    @Option(name: .customLong("build-path"))
    var buildPath: String?

    @Option(name: .customLong("config-path"))
    var configPath: String?

    @Option(name: .customLong("security-path"))
    var securityPath: String?

    @Flag(name: .customLong("disable-sandbox"))
    var disableSandbox = false

    @Flag(name: .customLong("enable-dependency-cache"))
    var enableDependencyCache = false

    @Flag(name: .customLong("disable-dependency-cache"))
    var disableDependencyCache = false

    @Flag(name: .customLong("skip-update"))
    var skipUpdate = false

    @Flag(name: .customLong("force-resolved-versions"))
    var forceResolvedVersions = false

    @Flag(name: .customLong("disable-automatic-resolution"))
    var disableAutomaticResolution = false

    @Flag(name: .customLong("only-use-versions-from-resolved-file"))
    var onlyUseVersionsFromResolvedFile = false

    @Flag(name: .customLong("replace-scm-with-registry"))
    var replaceSCMWithRegistry = false

    @Flag(name: .customLong("use-registry-identity-for-scm"))
    var useRegistryIdentityForSCM = false

    @Option(name: .customLong("default-registry-url"))
    var defaultRegistryURL: String?

    @Flag(name: .customLong("disable-scm-to-registry-transformation"))
    var disableSCMToRegistryTransformation = false

    @Flag(name: [.customShort("q"), .customLong("quiet")])
    var quiet = false

    @Flag(name: .customLong("disable-package-info-cache"))
    var disablePackageInfoCache = false

    @Option(name: .customLong("package-info-cache-path"))
    var packageInfoCachePath: String?

    @Option(name: .customLong("cached-directory-materialization"))
    var cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization?

    @Argument
    var action: CLIAction

    @Argument(parsing: .allUnrecognized)
    var commandArguments: [String] = []

    public init() {}

    public mutating func run() async throws {
        try await runAsync()
    }

    public mutating func runAsync() async throws {
        try await CLIRunner.run(try makeCLI())
    }

    func makeCLI() throws -> CLI {
        let command: CLI.Command
        switch action {
        case .resolve:
            command = .resolve(try ResolveArguments.parse(commandArguments).makeOptions())
        case .update:
            command = .update(try UpdateArguments.parse(commandArguments).makeOptions())
        case .restore:
            command = .restore(try RestoreArguments.parse(commandArguments).makeOptions())
        }

        return CLI(
            chdir: CLIPath.optional(chdir),
            packagePath: CLIPath.optional(packagePath),
            cachePath: CLIPath.optional(cachePath),
            scratchPath: CLIPath.optional(scratchPath),
            buildPath: CLIPath.optional(buildPath),
            configPath: CLIPath.optional(configPath),
            securityPath: CLIPath.optional(securityPath),
            disableSandbox: disableSandbox,
            enableDependencyCache: enableDependencyCache,
            disableDependencyCache: disableDependencyCache,
            skipUpdate: skipUpdate,
            forceResolvedVersions: forceResolvedVersions,
            disableAutomaticResolution: disableAutomaticResolution,
            onlyUseVersionsFromResolvedFile: onlyUseVersionsFromResolvedFile,
            replaceSCMWithRegistry: replaceSCMWithRegistry,
            useRegistryIdentityForSCM: useRegistryIdentityForSCM,
            defaultRegistryURL: defaultRegistryURL,
            disableSCMToRegistryTransformation: disableSCMToRegistryTransformation,
            quiet: quiet,
            disablePackageInfoCache: disablePackageInfoCache,
            packageInfoCachePath: CLIPath.optional(packageInfoCachePath),
            cachedDirectoryMaterialization: cachedDirectoryMaterialization,
            command: command
        )
    }
}

extension SwifterPMCachedDirectoryMaterialization: ExpressibleByArgument {
    public init?(argument: String) {
        try? self.init(configurationValue: argument)
    }
}

enum CLIParser {
    static func parse(_ args: [String]) throws -> CLI {
        try SwifterPMCommand.parse(args).makeCLI()
    }
}

private struct ResolveArguments: ParsableArguments {
    @Argument
    var packageName: String?

    @Option(name: .customLong("version"))
    var version: String?

    @Option(name: .customLong("branch"))
    var branch: String?

    @Option(name: .customLong("revision"))
    var revision: String?

    @Option(name: .customLong("package-dir"))
    var packageDir = "."

    @Option(name: .customLong("cache-dir"))
    var cacheDir: String?

    @Flag(name: .customLong("write"))
    var write = false

    @Flag(name: .customLong("restore"))
    var restore = false

    @Flag(name: .customLong("print-only"))
    var printOnly = false

    func makeOptions() -> CLI.ResolveOptions {
        CLI.ResolveOptions(
            packageName: packageName,
            version: version,
            branch: branch,
            revision: revision,
            packageDir: CLIPath(packageDir),
            cacheDir: CLIPath.optional(cacheDir),
            write: write,
            restore: restore,
            printOnly: printOnly
        )
    }
}

private struct UpdateArguments: ParsableArguments {
    @Argument
    var packageNames: [String] = []

    @Option(name: .customLong("package-dir"))
    var packageDir = "."

    @Option(name: .customLong("cache-dir"))
    var cacheDir: String?

    @Flag(name: .customLong("write"))
    var write = false

    @Flag(name: .customLong("restore"))
    var restore = false

    @Flag(name: .customLong("print-only"))
    var printOnly = false

    func makeOptions() -> CLI.UpdateOptions {
        CLI.UpdateOptions(
            packageNames: packageNames,
            packageDir: CLIPath(packageDir),
            cacheDir: CLIPath.optional(cacheDir),
            write: write,
            restore: restore,
            printOnly: printOnly
        )
    }
}

private struct RestoreArguments: ParsableArguments {
    @Option(name: .customLong("package-dir"))
    var packageDir = "."

    @Option(name: .customLong("cache-dir"))
    var cacheDir: String?

    @Option(name: .customLong("scratch-dir"))
    var scratchDir: String?

    func makeOptions() -> CLI.RestoreOptions {
        CLI.RestoreOptions(
            packageDir: CLIPath(packageDir),
            cacheDir: CLIPath.optional(cacheDir),
            scratchDir: CLIPath.optional(scratchDir)
        )
    }
}

struct CLIPathResolver {
    let baseDirectory: URL

    init(chdir: CLIPath?) async throws {
        let currentDirectory = URL(
            fileURLWithPath: try await fileSystem.currentWorkingDirectory().pathString,
            isDirectory: true
        )
        guard let chdir else {
            baseDirectory = currentDirectory.standardizedFileURL
            return
        }

        let resolvedChdir = chdir.resolved(relativeTo: currentDirectory)
        guard try await fileSystem.exists(resolvedChdir.absolutePath, isDirectory: true) else {
            throw ToolError.message("failed to change directory to \(resolvedChdir.path)")
        }
        baseDirectory = resolvedChdir.standardizedFileURL
    }

    func resolve(_ path: CLIPath?) -> URL? {
        path.map(resolve)
    }

    func resolve(_ path: CLIPath) -> URL {
        path.resolved(relativeTo: baseDirectory)
    }
}

enum CLIRunner {
    static func run(_ cli: CLI) async throws {
        try await Environment.withCachedDirectoryMaterialization(
            cli.cachedDirectoryMaterialization
        ) {
            let paths = try await CLIPathResolver(chdir: cli.chdir)

            switch cli.command {
            case .resolve(let options):
                try ensureWholePackageResolution(
                    packageName: options.packageName,
                    version: options.version,
                    branch: options.branch,
                    revision: options.revision
                )
                try await runResolutionCommand(
                    cli: cli,
                    paths: paths,
                    packageDir: options.packageDir,
                    cacheDir: options.cacheDir,
                    preferResolvedFile: true,
                    write: options.write,
                    restore: options.restore,
                    printOnly: options.printOnly
                )
            case .update(let options):
                if !options.packageNames.isEmpty {
                    throw ToolError.message("package-specific update is not supported yet")
                }
                try await runResolutionCommand(
                    cli: cli,
                    paths: paths,
                    packageDir: options.packageDir,
                    cacheDir: options.cacheDir,
                    preferResolvedFile: false,
                    write: options.write,
                    restore: options.restore,
                    printOnly: options.printOnly
                )
            case .restore(let options):
                let cache = try await Cache(
                    root: cliCacheDir(cli: cli, paths: paths, commandCacheDir: options.cacheDir))
                let package = canonicalPackageDir(
                    commandPackageDir(
                        cli: cli, paths: paths, commandPackageDir: options.packageDir))
                let scratch = commandScratchDir(
                    cli: cli, paths: paths, packageDir: package, commandScratchDir: options.scratchDir)
                let registryConfig = try await cliRegistryConfig(
                    cli: cli, paths: paths, package: package)
                let resolved = try await ResolvedFile.read(packageDir: package)
                try await WorkspaceRestorer.restorePackage(
                    scratchDir: scratch, packageDir: package, cache: cache, registryConfig: registryConfig,
                    resolved: resolved,
                    progress: cli.quiet ? nil : RestoreProgressReporter(),
                    disableSandbox: cli.disableSandbox)
                try await maybeWritePackageInfoCache(
                    cli: cli, paths: paths, package: package, scratch: scratch, resolved: resolved)
                try await WorkspaceRestorer.writeWorkspaceState(
                    packageDir: package, scratchDir: scratch, resolved: resolved,
                    disableSandbox: cli.disableSandbox)
            }
        }
    }

    private static func runResolutionCommand(
        cli: CLI,
        paths: CLIPathResolver,
        packageDir: CLIPath,
        cacheDir: CLIPath?,
        preferResolvedFile: Bool,
        write: Bool,
        restore: Bool,
        printOnly: Bool
    ) async throws {
        let cache = try await Cache(
            root: cliCacheDir(cli: cli, paths: paths, commandCacheDir: cacheDir))
        let package = canonicalPackageDir(
            commandPackageDir(cli: cli, paths: paths, commandPackageDir: packageDir))
        let scratch = commandScratchDir(
            cli: cli, paths: paths, packageDir: package, commandScratchDir: nil)
        let registryConfig = try await cliRegistryConfig(
            cli: cli, paths: paths, package: package)
        let readOnly =
            cli.forceResolvedVersions || cli.disableAutomaticResolution
            || cli.onlyUseVersionsFromResolvedFile

        let resolved = try await PackageResolver.resolveOrLoad(
            packageDir: package,
            scratchDir: scratch,
            cache: cache,
            registryConfig: registryConfig,
            registryConfigurationPath: paths.resolve(cli.configPath),
            defaultRegistryURL: cli.defaultRegistryURL,
            disableSandbox: cli.disableSandbox,
            scmToRegistryTransformation: try scmToRegistryTransformation(cli),
            preferResolvedFile: preferResolvedFile,
            readOnly: readOnly,
            skipUpdate: cli.skipUpdate,
            writeResolvedFile: shouldWrite(write: write, printOnly: printOnly),
            progress: cli.quiet ? nil : ResolutionProgressReporter()
        )

        if !cli.quiet {
            ResolvedFile.print(resolved)
        }
        if shouldRestore(restore: restore, printOnly: printOnly) {
            try await WorkspaceRestorer.restorePackage(
                scratchDir: scratch, packageDir: package, cache: cache, registryConfig: registryConfig,
                resolved: resolved,
                progress: cli.quiet ? nil : RestoreProgressReporter(),
                disableSandbox: cli.disableSandbox)
            try await maybeWritePackageInfoCache(
                cli: cli, paths: paths, package: package, scratch: scratch, resolved: resolved)
            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package, scratchDir: scratch, resolved: resolved,
                disableSandbox: cli.disableSandbox)
        }

        // `resolveOrLoad` rejected direct pins that violate the root manifest;
        // with the checkouts materialized, extend that to the whole pinned graph
        // (SwiftPM precomputation parity) so transitive drift fails here too.
        if readOnly {
            try await PackageResolver.validateResolvedGraphSatisfiesManifests(
                packageDir: package,
                scratchDir: scratch,
                resolved: resolved,
                disableSandbox: cli.disableSandbox
            )
        }
    }

    private static func maybeWritePackageInfoCache(
        cli: CLI, paths: CLIPathResolver, package: URL, scratch: URL, resolved: ResolvedPins
    ) async throws {
        if cli.disablePackageInfoCache {
            return
        }
        try await PackageInfoCacheWriter.write(
            packageDir: package,
            scratchDir: scratch,
            resolved: resolved,
            cacheDir: paths.resolve(cli.packageInfoCachePath),
            disableSandbox: cli.disableSandbox,
            quiet: cli.quiet
        )
    }

    static func scmToRegistryTransformation(_ cli: CLI) throws
        -> SCMToRegistryTransformation
    {
        let enabled = [
            cli.replaceSCMWithRegistry,
            cli.useRegistryIdentityForSCM,
            cli.disableSCMToRegistryTransformation,
        ].filter { $0 }.count
        if enabled > 1 {
            throw ToolError.message("source-control to registry transformation flags conflict")
        }
        if cli.replaceSCMWithRegistry {
            return .replaceSCMWithRegistry
        }
        if cli.useRegistryIdentityForSCM {
            return .useRegistryIdentityForSCM
        }
        return .disabled
    }

    static func ensureWholePackageResolution(
        packageName: String?, version: String?, branch: String?, revision: String?
    ) throws {
        if packageName != nil || version != nil || branch != nil || revision != nil {
            throw ToolError.message("package-specific resolve is not supported yet")
        }
    }

    static func shouldWrite(write: Bool, printOnly: Bool) -> Bool {
        !printOnly || write
    }

    static func shouldRestore(restore: Bool, printOnly: Bool) -> Bool {
        !printOnly || restore
    }

    static func cliCacheDir(cli: CLI, paths: CLIPathResolver, commandCacheDir: CLIPath?)
        -> URL?
    {
        paths.resolve(commandCacheDir ?? cli.cachePath)
    }

    private static func cliRegistryConfig(
        cli: CLI, paths: CLIPathResolver, package: URL
    ) async throws
        -> RegistryConfig
    {
        try await RegistryConfig.load(
            packageDir: package, configPath: paths.resolve(cli.configPath),
            defaultRegistryURL: cli.defaultRegistryURL)
    }

    static func commandPackageDir(
        cli: CLI, paths: CLIPathResolver, commandPackageDir: CLIPath
    )
        -> URL
    {
        paths.resolve(cli.packagePath ?? commandPackageDir)
    }

    static func commandScratchDir(
        cli: CLI, paths: CLIPathResolver, packageDir: URL, commandScratchDir: CLIPath?
    ) -> URL
    {
        if let scratchDir = commandScratchDir ?? cli.scratchPath ?? cli.buildPath {
            return paths.resolve(scratchDir)
        }
        return packageDir.appendingPathComponent(".build")
    }

    static func canonicalPackageDir(_ packageDir: URL) -> URL {
        packageDir.standardizedFileURL
    }
}
