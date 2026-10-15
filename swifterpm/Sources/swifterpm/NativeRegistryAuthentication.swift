import Foundation

/// Older SwiftPM cannot consume environment credentials. Only inline netrc can be
/// translated without changing credential scope; registry tokens are origin-scoped,
/// while a file netrc also authenticates HTTP downloads on every port of the host.
enum NativeRegistryAuthentication {
    enum Plan: Equatable {
        case native
        case inlineNetrc(String)
    }

    static let credentialVariables = [
        "SWIFTPM_REGISTRY_TOKEN", "SWIFTPM_REGISTRY_LOGIN", "SWIFTPM_REGISTRY_PASSWORD",
        "SWIFTPM_SOURCE_CONTROL_TOKEN", "SWIFTPM_NETRC_DATA",
    ]

    static func prepare(
        packageDir: URL,
        registryConfigurationPath: URL?,
        defaultRegistryURL: String?,
        disableSandbox: Bool,
        scmToRegistryTransformation: SCMToRegistryTransformation
    ) async throws -> Plan {
        let environment = Environment.current
        guard credentialVariables.contains(where: { nonEmpty(environment[$0]) != nil }) else { return .native }
        let version = try await SystemProcess.run(
            "swift", ["--version"], customEnvironment: Environment.manifestValues
        )
        if supportsEnvironmentCredentials(version.stdoutString), credentialVariables.allSatisfy({
            nonEmpty(environment[$0]) == nonEmpty(Environment.manifest[$0])
        }) { return .native }
        guard try await mayResolveRegistryDependencies(
            packageDir: packageDir, disableSandbox: disableSandbox,
            scmToRegistryTransformation: scmToRegistryTransformation
        ) else { return .native }
        let config = try await RegistryConfig.loadForNativeResolution(
            packageDir: packageDir, configPath: registryConfigurationPath, defaultRegistryURL: defaultRegistryURL
        )
        return try plan(
            versionOutput: version.stdoutString,
            environment: environment,
            childEnvironment: Environment.manifest,
            netrc: Environment.netrc,
            registryConfig: config
        )
    }

    /// Shared registry settings alone do not imply that a package uses a registry.
    /// Unknown transitive dependencies remain native SwiftPM's responsibility rather
    /// than blocking an otherwise working source-control-only resolution.
    static func mayResolveRegistryDependencies(
        packageDir: URL,
        disableSandbox: Bool,
        scmToRegistryTransformation: SCMToRegistryTransformation
    ) async throws -> Bool {
        let manifest = try await ManifestLoader.dumpPackage(packageDir: packageDir, disableSandbox: disableSandbox)
        let localPackages = try await ManifestFileSystemDependencyGraph.collect(
            rootPackageDir: packageDir, rootManifest: manifest, disableSandbox: disableSandbox
        )
        let dependencies = try ([manifest] + localPackages.map(\.manifest)).flatMap { try ManifestParser.dependencies($0) }
        if dependencies.contains(where: { $0.kind == .registry }) { return true }
        guard dependencies.contains(where: { $0.kind == .sourceControl }) else { return false }
        if scmToRegistryTransformation != .disabled { return true }
        if let resolved = try? await ResolvedFile.read(packageDir: packageDir),
           resolved.pins.contains(where: { $0.kind == "registry" }) { return true }
        return false
    }

    static func plan(
        versionOutput: String,
        environment: [String: String],
        childEnvironment: [String: String],
        netrc: Netrc,
        registryConfig: RegistryConfig
    ) throws -> Plan {
        guard !registryConfig.registryURLs.isEmpty else { return .native }
        // Upstream's 6.3.1 release lacks these providers; 6.3.2 includes them.
        // Unknown version strings take the conservative compatibility path.
        let hasRegistryToken = nonEmpty(environment["SWIFTPM_REGISTRY_TOKEN"]) != nil
        let hasRegistryLogin = nonEmpty(environment["SWIFTPM_REGISTRY_LOGIN"]) != nil
            && nonEmpty(environment["SWIFTPM_REGISTRY_PASSWORD"]) != nil
        var selectedVariables: [String] = []
        if hasRegistryToken {
            selectedVariables.append("SWIFTPM_REGISTRY_TOKEN")
        } else if hasRegistryLogin {
            selectedVariables += ["SWIFTPM_REGISTRY_LOGIN", "SWIFTPM_REGISTRY_PASSWORD"]
        }
        if netrc.hasEnvironmentSource { selectedVariables.append("SWIFTPM_NETRC_DATA") }
        if nonEmpty(environment["SWIFTPM_SOURCE_CONTROL_TOKEN"]) != nil {
            selectedVariables.append("SWIFTPM_SOURCE_CONTROL_TOKEN")
        }
        if supportsEnvironmentCredentials(versionOutput), selectedVariables.allSatisfy({
            nonEmpty(environment[$0]) == nonEmpty(childEnvironment[$0])
        }) {
            return .native
        }
        if hasRegistryToken || hasRegistryLogin {
            throw ToolError.message(
                "native SwiftPM cannot use the configured environment credentials without changing their scope. "
                    + "Use a toolchain with environment credential support (upstream Swift 6.3.2 or later), "
                    + "or explicitly configure host-scoped SWIFTPM_NETRC_DATA with registry authentication types. "
                    + "Do not exclude resolver credentials from the native subprocess environment. "
                    + "When choosing file/keychain credentials instead, unset the environment credential variables first."
            )
        }
        guard netrc.hasEnvironmentSource,
              registryConfig.registryURLs.contains(where: { netrc.credential(for: $0, from: .environment) != nil })
        else { return .native }
        guard nonEmpty(environment["SWIFTPM_SOURCE_CONTROL_TOKEN"]) == nil else {
            throw ToolError.message(
                "cannot bridge inline netrc while SWIFTPM_SOURCE_CONTROL_TOKEN selects global HTTP credentials. "
                    + "Unset that token when explicitly choosing host-scoped netrc, or use a newer toolchain."
            )
        }
        guard !netrc.configuration.isEnabled || netrc.machines(from: .file).isEmpty else {
            throw ToolError.message(
                "cannot bridge SWIFTPM_NETRC_DATA while file netrc credentials are enabled: "
                    + "older SwiftPM shares one file between registry and HTTP authentication. "
                    + "Use --disable-netrc to explicitly disable file credentials, or use a newer toolchain."
            )
        }
        for registryURL in registryConfig.registryURLs where netrc.credential(for: registryURL, from: .environment) != nil {
            guard registryConfig.authenticationType(for: registryURL) != nil else {
                throw ToolError.message(
                    "native SwiftPM requires an authentication type for \(registryURL.host ?? "the registry") "
                        + "in registries.json. Configure authentication.<host[:port]>.type as token or basic."
                )
            }
        }
        return .inlineNetrc(try serializedInlineNetrc(netrc.machines(from: .environment)))
    }

    static func supportsEnvironmentCredentials(_ output: String) -> Bool {
        for marker in ["Apple Swift version ", "Swift version "] {
            guard let range = output.range(of: marker) else { continue }
            let components = output[range.upperBound...]
                .prefix(while: { $0.isNumber || $0 == "." })
                .split(separator: ".").compactMap { Int($0) }
            guard components.count >= 2 else { return false }
            let patch = components.count > 2 ? components[2] : 0
            return components[0] > 6
                || (components[0] == 6 && (components[1] > 3 || (components[1] == 3 && patch >= 2)))
        }
        return false
    }

    static func serializedInlineNetrc(_ machines: [NetrcMachine]) throws -> String {
        var seen = Set<String>()
        return try machines.filter { seen.insert($0.name).inserted }.map { machine in
            let values = [machine.name, machine.login, machine.password]
            guard values
                .allSatisfy({ !$0.isEmpty && !$0.contains("\"") && !$0.contains("#") && !$0.contains("\0")
                        && !$0.contains(where: \.isWhitespace) })
            else {
                throw ToolError.message("inline netrc contains a credential that cannot be represented safely for older SwiftPM")
            }
            // Swift 6.0 treats quotes as literal characters, not token delimiters.
            let location = machine.isDefault ? "default" : "machine \(machine.name)"
            return "\(location) login \(machine.login) password \(machine.password)\n"
        }.joined()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A separate lifetime owner avoids changing signal handlers in an embedded CLI.
    /// Secrets arrive only on stdin, never in argv or an extra environment variable.
    /// The owner removes its private directory on exit, signals, or launcher death.
    static let credentialOwnerScript = """
    set -eu
    original_umask=$(umask)
    umask 077
    directory=''
    child=''
    watcher=''
    cleanup() {
        status=$?
        trap - EXIT HUP INT TERM
        if [ -n "$child" ]; then
            kill -TERM "$child" 2>/dev/null || true
            wait "$child" 2>/dev/null || true
        fi
        if [ -n "$watcher" ]; then
            kill -TERM "$watcher" 2>/dev/null || true
            wait "$watcher" 2>/dev/null || true
        fi
        if [ -n "$directory" ]; then
            /bin/rm -f "$directory/netrc"
            /bin/rmdir "$directory"
        fi
        exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    owner=$PPID
    guardian=$$
    directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/swifterpm-netrc.XXXXXXXX")
    (
        while kill -0 "$owner" 2>/dev/null && kill -0 "$guardian" 2>/dev/null; do /bin/sleep 1; done
        if kill -0 "$guardian" 2>/dev/null; then
            kill -TERM "$guardian" 2>/dev/null || true
        else
            /bin/rm -f "$directory/netrc"
            /bin/rmdir "$directory"
        fi
    ) </dev/null >/dev/null 2>&1 &
    watcher=$!
    /bin/cat > "$directory/netrc"
    umask "$original_umask"
    executable=$1
    shift
    command=$1
    shift
    "$executable" "$command" --netrc --netrc-file "$directory/netrc" "$@" </dev/null &
    child=$!
    status=0
    wait "$child" || status=$?
    child=''
    exit "$status"
    """
}
