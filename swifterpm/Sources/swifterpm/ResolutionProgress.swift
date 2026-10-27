import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#endif

final class ResolutionProgressReporter: @unchecked Sendable {
    private struct State {
        let startedAt = Date()
        let rootVersionedDependencies: Int
        let fixedDependencies: Int
        var fetchedMetadata = Set<String>()
        var inspectedManifests = Set<String>()
        var selectedPackages = Set<String>()
        var fixedPinPackages = Set<String>()
        var discoveredPackages = 0
        var lastProgressAt = Date.distantPast
        var lastProgressLine: String?
    }

    private let enabled: Bool
    private let minimumInterval: TimeInterval
    private let writeLine: @Sendable (String) -> Void
    private let lock = NSLock()
    private var state: State?

    init(
        enabled: Bool = true,
        minimumInterval: TimeInterval = 2,
        writeLine: @escaping @Sendable (String) -> Void = { line in
            ResolutionProgressReporter.writeStdout(line + "\n")
        }
    ) {
        self.enabled = enabled
        self.minimumInterval = minimumInterval
        self.writeLine = writeLine
    }

    func started(rootVersionedDependencies: Int, fixedDependencies: Int) {
        guard enabled else { return }
        withLock {
            state = State(
                rootVersionedDependencies: rootVersionedDependencies,
                fixedDependencies: fixedDependencies
            )
            writeLine("\(TerminalStyle.bold("swifterpm")) \(TerminalStyle.dim(swifterpmVersion))")
        }
    }

    func startedFetchingVersions(package: String) {
        emitProgress()
    }

    func finishedFetchingVersions(package: String, versionCount: Int) {
        withLock {
            guard var current = state else { return }
            current.fetchedMetadata.insert(package)
            state = current
        }
        emitProgress()
    }

    func selected(package: String, version: String) {
        withLock {
            guard var current = state else { return }
            current.selectedPackages.insert(package)
            state = current
        }
        emitProgress()
    }

    func startedInspectingManifest(package: String, version: String) {
        emitProgress()
    }

    func finishedInspectingManifest(package: String, version: String, dependencyCount: Int) {
        withLock {
            guard var current = state else { return }
            current.inspectedManifests.insert("\(package)@\(version)")
            current.discoveredPackages += dependencyCount
            state = current
        }
        emitProgress()
    }

    func startedResolvingFixedPin(package: String) {
        emitProgress()
    }

    func finishedResolvingFixedPin(package: String) {
        withLock {
            guard var current = state else { return }
            current.fixedPinPackages.insert(package)
            state = current
        }
        emitProgress()
    }

    func finished(pinCount: Int) {
        guard enabled else { return }
        withLock {
            guard let current = state else { return }
            let elapsed = TerminalStyle.dim(
                Self.formatDuration(Date().timeIntervalSince(current.startedAt)))
            let summary =
                "\(TerminalStyle.green("✓")) resolved \(TerminalStyle.bold("\(pinCount)")) package\(pinCount == 1 ? "" : "s") in \(elapsed)"
            writeLine(summary)
            state = nil
        }
    }

    private func emitProgress() {
        guard enabled else { return }
        withLock {
            guard var current = state else { return }
            let now = Date()
            guard now.timeIntervalSince(current.lastProgressAt) >= minimumInterval else {
                state = current
                return
            }
            let line = Self.progressLine(state: current)
            guard current.lastProgressLine != line else {
                state = current
                return
            }
            current.lastProgressAt = now
            current.lastProgressLine = line
            writeLine(line)
            state = current
        }
    }

    private static func progressLine(state: State) -> String {
        let resolvedPackages = state.selectedPackages.union(state.fixedPinPackages).count
        let targetPackages = max(
            state.rootVersionedDependencies + state.fixedDependencies + state.discoveredPackages,
            resolvedPackages
        )
        let count: String
        if targetPackages > resolvedPackages {
            count =
                "\(paddedCount(resolvedPackages, total: targetPackages))/\(targetPackages)"
        } else {
            count = paddedCount(resolvedPackages, total: resolvedPackages)
        }
        return
            "\(TerminalStyle.bold(count)) \(TerminalStyle.dim("deps")) \(TerminalStyle.dim("·")) \(TerminalStyle.cyan("resolving"))"
    }

    private static func paddedCount(_ count: Int, total: Int) -> String {
        let width = max(4, String(total).count)
        return String(format: "%\(width)d", count)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func writeStdout(_ output: String) {
        FileHandle.standardOutput.write(Data(output.utf8))
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let totalSeconds = Int(seconds.rounded())
        return "\(totalSeconds / 60)m\(String(format: "%02d", totalSeconds % 60))s"
    }
}

/// Routes binary-artifact restore progress to an output sink. Passing `nil`
/// (instead of a `quiet` flag) means silent, mirroring how the resolution path
/// uses an optional `ResolutionProgressReporter`. The reporter owns the message
/// formatting; callers own where the output goes.
final class RestoreProgressReporter: Sendable {
    private let emit: @Sendable (String) -> Void

    init(emit: @escaping @Sendable (String) -> Void = { Swift.print($0) }) {
        self.emit = emit
    }

    func downloadingBinaryArtifact(identity: String, target: String) {
        emit("downloading \(identity).\(target)")
    }

    func restoredBinaryArtifact(identity: String, target: String, path: String) {
        emit("restored \(identity).\(target) -> \(path)")
    }

    func restoredPackage(identity: String, path: String) {
        emit("restored \(identity) -> \(path)")
    }

    func restoreSummary(
        sourceCount: Int,
        sourcePath: String,
        registryCount: Int,
        registryPath: String,
        skipped: Int
    ) {
        emit("restored \(sourceCount) source-control packages into \(sourcePath)")
        emit("restored \(registryCount) registry packages into \(registryPath)")
        if skipped > 0 {
            emit("skipped \(skipped) unsupported pins")
        }
    }
}

private enum TerminalStyle {
    static func bold(_ value: String) -> String {
        styled(value, code: "1")
    }

    static func cyan(_ value: String) -> String {
        styled(value, code: "36")
    }

    static func dim(_ value: String) -> String {
        styled(value, code: "2")
    }

    static func green(_ value: String) -> String {
        styled(value, code: "32")
    }

    private static func styled(_ value: String, code: String) -> String {
        guard colorEnabled else { return value }
        return "\u{001B}[\(code)m\(value)\u{001B}[0m"
    }

    fileprivate static var colorEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["NO_COLOR"] != nil {
            return false
        }
        if let force = env["CLICOLOR_FORCE"], truthy(force) {
            return true
        }
        if env["CLICOLOR"] == "0" {
            return false
        }
        return isatty(FileHandle.standardOutput.fileDescriptor) == 1
    }

    private static func truthy(_ value: String) -> Bool {
        !["", "0", "false", "no", "off"].contains(value.lowercased())
    }
}
