import Foundation

public enum SCMToRegistryTransformation: Equatable, Sendable {
    case disabled
    case useRegistryIdentityForSCM
    case replaceSCMWithRegistry
}

public enum SwifterPMCachedDirectoryMaterialization: String, CaseIterable, Equatable, Sendable {
    case automatic
    case copy
    case symlink
}

public struct SwifterPMResolvedPin: Equatable, Sendable {
    public let identity: String
    public let kind: String
    public let location: String
    public let branch: String?
    public let revision: String?
    public let version: String?
    /// The SCM URL the pin was originally declared as before
    /// `--replace-scm-with-registry` mapped it to a registry identity, when
    /// applicable. Present so embedders can correlate registry pins back to
    /// the manifest URL without re-querying the registry.
    public let originalLocation: String?
}

public struct SwifterPMResolutionResult: Sendable {
    public let originHash: String?
    public let pins: [SwifterPMResolvedPin]
}

public struct SwifterPMResolutionRequest: Sendable {
    public var packageDirectory: URL
    public var cacheDirectory: URL?
    public var scratchDirectory: URL?
    public var registryConfigurationPath: URL?
    public var defaultRegistryURL: String?
    public var disableSandbox: Bool
    public var forceResolvedVersions: Bool
    public var skipUpdate: Bool
    public var writeResolvedFile: Bool
    public var restorePackage: Bool
    public var disablePackageInfoCache: Bool
    public var packageInfoCacheDirectory: URL?
    public var scmToRegistryTransformation: SCMToRegistryTransformation
    public var cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization?
    public var quiet: Bool

    public init(
        packageDirectory: URL,
        cacheDirectory: URL? = nil,
        scratchDirectory: URL? = nil,
        registryConfigurationPath: URL? = nil,
        defaultRegistryURL: String? = nil,
        disableSandbox: Bool = false,
        forceResolvedVersions: Bool = false,
        skipUpdate: Bool = false,
        writeResolvedFile: Bool = true,
        restorePackage: Bool = true,
        disablePackageInfoCache: Bool = false,
        packageInfoCacheDirectory: URL? = nil,
        scmToRegistryTransformation: SCMToRegistryTransformation = .disabled,
        cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization? = nil,
        quiet: Bool = false
    ) {
        self.packageDirectory = packageDirectory
        self.cacheDirectory = cacheDirectory
        self.scratchDirectory = scratchDirectory
        self.registryConfigurationPath = registryConfigurationPath
        self.defaultRegistryURL = defaultRegistryURL
        self.disableSandbox = disableSandbox
        self.forceResolvedVersions = forceResolvedVersions
        self.skipUpdate = skipUpdate
        self.writeResolvedFile = writeResolvedFile
        self.restorePackage = restorePackage
        self.disablePackageInfoCache = disablePackageInfoCache
        self.packageInfoCacheDirectory = packageInfoCacheDirectory
        self.scmToRegistryTransformation = scmToRegistryTransformation
        self.cachedDirectoryMaterialization = cachedDirectoryMaterialization
        self.quiet = quiet
    }
}

public struct SwifterPMRestoreRequest: Sendable {
    public var packageDirectory: URL
    public var cacheDirectory: URL?
    public var scratchDirectory: URL?
    public var registryConfigurationPath: URL?
    public var defaultRegistryURL: String?
    public var disableSandbox: Bool
    public var disablePackageInfoCache: Bool
    public var packageInfoCacheDirectory: URL?
    public var cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization?
    public var quiet: Bool

    public init(
        packageDirectory: URL,
        cacheDirectory: URL? = nil,
        scratchDirectory: URL? = nil,
        registryConfigurationPath: URL? = nil,
        defaultRegistryURL: String? = nil,
        disableSandbox: Bool = false,
        disablePackageInfoCache: Bool = false,
        packageInfoCacheDirectory: URL? = nil,
        cachedDirectoryMaterialization: SwifterPMCachedDirectoryMaterialization? = nil,
        quiet: Bool = false
    ) {
        self.packageDirectory = packageDirectory
        self.cacheDirectory = cacheDirectory
        self.scratchDirectory = scratchDirectory
        self.registryConfigurationPath = registryConfigurationPath
        self.defaultRegistryURL = defaultRegistryURL
        self.disableSandbox = disableSandbox
        self.disablePackageInfoCache = disablePackageInfoCache
        self.packageInfoCacheDirectory = packageInfoCacheDirectory
        self.cachedDirectoryMaterialization = cachedDirectoryMaterialization
        self.quiet = quiet
    }
}

public struct SwifterPM: Sendable {
    public init() {}

    public func resolve(_ request: SwifterPMResolutionRequest) async throws
        -> SwifterPMResolutionResult
    {
        try await Environment.withCachedDirectoryMaterialization(
            request.cachedDirectoryMaterialization
        ) {
            try await runResolution(request: request, preferResolvedFile: true)
        }
    }

    public func update(_ request: SwifterPMResolutionRequest) async throws
        -> SwifterPMResolutionResult
    {
        try await Environment.withCachedDirectoryMaterialization(
            request.cachedDirectoryMaterialization
        ) {
            try await runResolution(request: request, preferResolvedFile: false)
        }
    }

    public func restore(_ request: SwifterPMRestoreRequest) async throws {
        try await Environment.withCachedDirectoryMaterialization(
            request.cachedDirectoryMaterialization
        ) {
            try await runRestore(request)
        }
    }

    private func runRestore(_ request: SwifterPMRestoreRequest) async throws {
        let package = request.packageDirectory.standardizedFileURL
        let scratch = request.scratchDirectory ?? package.appendingPathComponent(".build")
        let cache = try await Cache(root: request.cacheDirectory)
        let registryConfig = try await RegistryConfig.load(
            packageDir: package,
            configPath: request.registryConfigurationPath,
            defaultRegistryURL: request.defaultRegistryURL
        )
        let resolved = try await ResolvedFile.read(packageDir: package)
        try await WorkspaceRestorer.restorePackage(
            scratchDir: scratch,
            packageDir: package,
            cache: cache,
            registryConfig: registryConfig,
            resolved: resolved,
            progress: request.quiet ? nil : RestoreProgressReporter(),
            disableSandbox: request.disableSandbox
        )
        try await maybeWritePackageInfoCache(
            packageDir: package,
            scratchDir: scratch,
            resolved: resolved,
            cacheDir: request.packageInfoCacheDirectory,
            disablePackageInfoCache: request.disablePackageInfoCache,
            disableSandbox: request.disableSandbox,
            quiet: request.quiet
        )
        try await WorkspaceRestorer.writeWorkspaceState(
            packageDir: package,
            scratchDir: scratch,
            resolved: resolved,
            disableSandbox: request.disableSandbox
        )
    }

    private func runResolution(
        request: SwifterPMResolutionRequest,
        preferResolvedFile: Bool
    ) async throws -> SwifterPMResolutionResult {
        let package = request.packageDirectory.standardizedFileURL
        let scratch = request.scratchDirectory ?? package.appendingPathComponent(".build")
        let cache = try await Cache(root: request.cacheDirectory)
        let registryConfig = try await RegistryConfig.load(
            packageDir: package,
            configPath: request.registryConfigurationPath,
            defaultRegistryURL: request.defaultRegistryURL
        )

        let resolved = try await PackageResolver.resolveOrLoad(
            packageDir: package,
            scratchDir: scratch,
            cache: cache,
            registryConfig: registryConfig,
            registryConfigurationPath: request.registryConfigurationPath,
            defaultRegistryURL: request.defaultRegistryURL,
            disableSandbox: request.disableSandbox,
            scmToRegistryTransformation: request.scmToRegistryTransformation,
            preferResolvedFile: preferResolvedFile,
            readOnly: request.forceResolvedVersions,
            skipUpdate: request.skipUpdate,
            writeResolvedFile: request.writeResolvedFile,
            progress: request.quiet ? nil : ResolutionProgressReporter()
        )

        if !request.quiet {
            ResolvedFile.print(resolved)
        }
        if request.restorePackage {
            try await WorkspaceRestorer.restorePackage(
                scratchDir: scratch,
                packageDir: package,
                cache: cache,
                registryConfig: registryConfig,
                resolved: resolved,
                progress: request.quiet ? nil : RestoreProgressReporter(),
                disableSandbox: request.disableSandbox
            )
            try await maybeWritePackageInfoCache(
                packageDir: package,
                scratchDir: scratch,
                resolved: resolved,
                cacheDir: request.packageInfoCacheDirectory,
                disablePackageInfoCache: request.disablePackageInfoCache,
                disableSandbox: request.disableSandbox,
                quiet: request.quiet
            )
            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package,
                scratchDir: scratch,
                resolved: resolved,
                disableSandbox: request.disableSandbox
            )
        }

        // `resolveOrLoad` already rejected a `Package.resolved` whose direct
        // pins violate the root manifest. With the checkouts now materialized we
        // can extend that to the whole pinned graph (SwiftPM's precomputation
        // parity), catching transitive constraints the root never names.
        if request.forceResolvedVersions {
            try await PackageResolver.validateResolvedGraphSatisfiesManifests(
                packageDir: package,
                scratchDir: scratch,
                resolved: resolved,
                disableSandbox: request.disableSandbox
            )
        }

        return SwifterPMResolutionResult(resolved)
    }

    private func maybeWritePackageInfoCache(
        packageDir: URL,
        scratchDir: URL,
        resolved: ResolvedPins,
        cacheDir: URL?,
        disablePackageInfoCache: Bool,
        disableSandbox: Bool,
        quiet: Bool
    ) async throws {
        guard !disablePackageInfoCache else { return }
        try await PackageInfoCacheWriter.write(
            packageDir: packageDir,
            scratchDir: scratchDir,
            resolved: resolved,
            cacheDir: cacheDir,
            disableSandbox: disableSandbox,
            quiet: quiet
        )
    }
}

extension SwifterPMResolutionResult {
    init(_ resolved: ResolvedPins) {
        originHash = resolved.originHash
        pins = resolved.pins.map(SwifterPMResolvedPin.init)
    }
}

extension SwifterPMResolvedPin {
    init(_ pin: ResolvedPin) {
        identity = pin.identity
        kind = pin.kind
        location = pin.location
        branch = pin.state.branch
        revision = pin.state.revision
        version = pin.state.version
        originalLocation = pin.originalLocation
    }
}
