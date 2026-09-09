import Command
import Foundation
import Mockable
import Path

public enum LaunchAgentDomain: String, CaseIterable, Sendable {
    case gui
    case user

    var target: String { "\(rawValue)/\(getuid())" }

    /// launchd requires Background for the user domain. Restricting the plist to
    /// that session also prevents a later GUI login from starting a second copy.
    var sessionType: String {
        switch self {
        case .gui: "Aqua"
        case .user: "Background"
        }
    }
}

/// Utility to interact with the `launchctl` CLI.
@Mockable
public protocol LaunchctlControlling {
    /// Prefers the GUI domain when available, otherwise the background user domain.
    func preferredDomain() async throws -> LaunchAgentDomain

    /// Bootstraps a LaunchAgent whose session type matches the selected domain.
    func bootstrap(plistPath: AbsolutePath, domain: LaunchAgentDomain) async throws

    /// Boots out the label from both domains, including agents installed before a GUI login.
    func bootout(label: String) async throws

    /// Restarts a LaunchAgent in the domain where it is loaded.
    func kickstart(label: String) async throws

    /// Returns whether the label is loaded in the GUI or background user domain.
    func isLoaded(label: String) async throws -> Bool
}

public struct LaunchctlController: LaunchctlControlling {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func preferredDomain() async throws -> LaunchAgentDomain {
        do {
            _ = try await commandRunner.run(arguments: ["/bin/launchctl", "print", LaunchAgentDomain.gui.target])
                .awaitCompletion()
            return .gui
        } catch let error as CommandError {
            guard case let .terminated(code, stderr, _) = error,
                  Self.describesAMissingDomain(code: code, stderr: stderr)
            else { throw error }
        }

        _ = try await commandRunner.run(arguments: ["/bin/launchctl", "print", LaunchAgentDomain.user.target])
            .awaitCompletion()
        return .user
    }

    public func bootstrap(plistPath: AbsolutePath, domain: LaunchAgentDomain) async throws {
        _ = try await commandRunner.run(
            arguments: [
                "/bin/launchctl",
                "bootstrap",
                domain.target,
                plistPath.pathString,
            ]
        )
        .awaitCompletion()
    }

    public func bootout(label: String) async throws {
        for domain in LaunchAgentDomain.allCases where try await isLoaded(label: label, domain: domain) {
            _ = try await commandRunner.run(
                arguments: ["/bin/launchctl", "bootout", "\(domain.target)/\(label)"]
            )
            .awaitCompletion()
        }
    }

    public func kickstart(label: String) async throws {
        let domain: LaunchAgentDomain
        if let loadedDomain = try await loadedDomain(label: label) {
            domain = loadedDomain
        } else {
            domain = try await preferredDomain()
        }
        _ = try await commandRunner.run(
            arguments: [
                "/bin/launchctl",
                "kickstart",
                "-k",
                "\(domain.target)/\(label)",
            ]
        )
        .awaitCompletion()
    }

    public func isLoaded(label: String) async throws -> Bool {
        try await loadedDomain(label: label) != nil
    }

    private func loadedDomain(label: String) async throws -> LaunchAgentDomain? {
        for domain in LaunchAgentDomain.allCases where try await isLoaded(label: label, domain: domain) {
            return domain
        }
        return nil
    }

    private func isLoaded(label: String, domain: LaunchAgentDomain) async throws -> Bool {
        do {
            _ = try await commandRunner.run(
                arguments: [
                    "/bin/launchctl",
                    "print",
                    "\(domain.target)/\(label)",
                ]
            )
            .awaitCompletion()
            return true
        } catch let error as CommandError {
            guard case let .terminated(code, stderr, _) = error else { throw error }
            guard Self.describesAMissingService(code: code, stderr: stderr)
                || Self.describesAMissingDomain(code: code, stderr: stderr)
            else { throw error }
            return false
        }
    }

    private static func describesAMissingDomain(code: Int32, stderr: String) -> Bool {
        let message = stderr.lowercased()
        return (code == 125 && message.contains("domain does not support specified action"))
            || (code == 112 && message.contains("could not find domain"))
    }

    /// `launchctl print` exits non-zero both for a service that is not there and
    /// for every other failure, so only the missing-service termination may be
    /// read as "not loaded". Reading the rest that way reports a loaded agent as
    /// absent, which skips the bootout and leaves the bootstrap after it landing
    /// on a live label.
    ///
    /// Matched on the code and the wording together because neither is a
    /// contract: launchctl's status for a missing service is not stable across
    /// macOS versions, and a reworded message under a known code still has to
    /// resolve.
    private static func describesAMissingService(code: Int32, stderr: String) -> Bool {
        code == 113 || code == ESRCH
            || stderr.lowercased().contains("could not find service")
    }
}
