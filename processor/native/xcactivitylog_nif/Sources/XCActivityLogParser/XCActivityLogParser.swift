import Foundation
import Path
import XCLogParser

public struct XCActivityLogParser: Sendable {
    public init() {}

    public func parse(
        xcactivitylogURL: URL,
        casAnalyticsDatabasePath: AbsolutePath,
        legacyCASMetadataPath: AbsolutePath? = nil
    ) async throws -> BuildData {
        let activityLog = try ActivityParser().parseActivityLogInURL(
            xcactivitylogURL,
            redacted: false,
            withoutBuildSpecificInformation: false
        )

        let buildStep = try ParserBuildSteps(
            omitWarningsDetails: false,
            omitNotesDetails: false,
            truncLargeIssues: false
        ).parse(activityLog: activityLog)

        let steps = flattenBuildSteps([buildStep])
        let targetSteps = steps.filter { $0.type == .target && $0.title.contains("Build target ") }

        let category = determineCategory(steps: steps, targetSteps: targetSteps, activityLog: activityLog)
        let errorCount = steps.reduce(0) { acc, step in
            (step.errors ?? []).filter { $0.severity == 2 }.count + acc
        }

        let targets = targetSteps.map { step -> Target in
            let subSteps = flattenBuildSteps([step])
            let hasErrors = subSteps.contains { ($0.errors ?? []).contains { $0.severity == 2 } }
            return Target(
                name: step.title.replacingOccurrences(of: "Build target ", with: ""),
                project: extractProject(from: subSteps.first { extractProject(from: [$0]).first?.project != "" }
                    .map { [$0] } ?? []).first?.project ?? "",
                build_duration: Int((step.duration * 1000).rounded(.up)),
                compilation_duration: Int((step.compilationDuration * 1000).rounded(.up)),
                status: hasErrors ? "failure" : "success"
            )
        }

        let issues = extractIssues(from: steps)
        let files = extractFiles(from: steps)

        let casReader = CASMetadataReader(
            databasePath: casAnalyticsDatabasePath,
            legacyCASMetadataPath: legacyCASMetadataPath
        )

        let cacheableTasks = try await analyzeCacheableTasks(
            buildSteps: steps,
            casReader: casReader
        )
        let casOutputs = try await analyzeCASOutputs(
            from: steps,
            casReader: casReader
        )

        let duration = Int(activityLog.mainSection.timeStoppedRecording * 1000)
            - Int(activityLog.mainSection.timeStartedRecording * 1000)

        return BuildData(
            unique_identifier: activityLog.mainSection.uniqueIdentifier,
            version: activityLog.version,
            time_started_recording: activityLog.mainSection.timeStartedRecording,
            time_stopped_recording: activityLog.mainSection.timeStoppedRecording,
            duration: duration,
            error_count: errorCount,
            status: errorCount == 0 ? "success" : "failure",
            category: category == .clean ? "clean" : "incremental",
            targets: targets,
            issues: Array(issues.prefix(1000)),
            files: files,
            cacheable_tasks: cacheableTasks,
            cas_outputs: casOutputs
        )
    }

    // MARK: - Build Steps

    private func flattenBuildSteps(_ steps: [BuildStep]) -> [BuildStep] {
        steps.flatMap { step in
            var flattened = [step]
            if !step.subSteps.isEmpty {
                flattened.append(contentsOf: flattenBuildSteps(step.subSteps))
            }
            return flattened
        }
    }

    // MARK: - Category

    private enum BuildCategory {
        case clean, incremental
    }

    private func determineCategory(
        steps: [BuildStep],
        targetSteps: [BuildStep],
        activityLog: IDEActivityLog
    ) -> BuildCategory {
        let hasCompilationCache = steps.contains {
            $0.title.contains("Swift caching") || $0.title.contains("Clang caching")
        }
        if hasCompilationCache {
            let mainBuildStartTimestamp = Date(
                timeIntervalSinceReferenceDate: activityLog.mainSection.timeStartedRecording
            ).timeIntervalSince1970
            let hasStaleTargets = targetSteps.contains { $0.startTimestamp < mainBuildStartTimestamp }
            return hasStaleTargets ? .incremental : .clean
        }

        let detailSteps = steps.filter { $0.type == .detail && $0.detailStepType != .swiftAggregatedCompilation }
        let buildSteps = detailSteps.filter {
            $0.detailStepType != .other && $0.detailStepType != .scriptExecution && $0.detailStepType != .copySwiftLibs
        }

        let targetIdentifiers = buildTargetIdentifiers(from: steps)
        var targetsCompiledCount = [String: Int]()
        for target in targetSteps {
            targetsCompiledCount[target.identifier] = 0
        }

        for step in buildSteps where !step.fetchedFromCache {
            guard let targetID = targetIdentifiers[step.identifier] else { continue }
            targetsCompiledCount[targetID, default: 0] += 1
        }

        var cleanCount = 0
        for (target, filesCompiledCount) in targetsCompiledCount {
            let targetFilesCount = buildSteps.filter { targetIdentifiers[$0.identifier] == target }.count
            if filesCompiledCount == targetFilesCount && filesCompiledCount > 0 {
                cleanCount += 1
            }
        }

        return cleanCount > targetSteps.count / 2 ? .clean : .incremental
    }

    private func buildTargetIdentifiers(from steps: [BuildStep]) -> [String: String] {
        let targetBuildSteps = steps.filter { $0.type == .target && $0.title.contains("Build target ") }
        var identifiers = [String: String]()
        for t in targetBuildSteps { identifiers[t.identifier] = t.identifier }

        let detailSteps = steps.filter { $0.type == .detail && $0.detailStepType != .swiftAggregatedCompilation }
        let swiftAggregated = steps.filter { $0.type == .detail && $0.detailStepType == .swiftAggregatedCompilation }
        var aggMap = [String: String]()
        for s in swiftAggregated { aggMap[s.identifier] = s.parentIdentifier }

        for step in detailSteps.filter({ $0.detailStepType != .swiftCompilation }) {
            identifiers[step.identifier] = step.parentIdentifier
        }
        for step in detailSteps.filter({ $0.detailStepType == .swiftCompilation }) {
            if identifiers[step.parentIdentifier] == nil {
                if let id = aggMap[step.parentIdentifier] {
                    identifiers[step.identifier] = id
                }
            } else {
                identifiers[step.identifier] = step.parentIdentifier
            }
        }
        return identifiers
    }

    // MARK: - Issues

    private func extractIssues(from steps: [BuildStep]) -> [Issue] {
        var seen = Set<String>()
        var result = [Issue]()
        for step in steps {
            let errors = step.errors ?? []
            let warnings = step.warnings ?? []
            for notice in errors + warnings {
                let issueType: String = notice.severity == 1 ? "warning" : "error"
                var message = notice.detail
                if var detail = notice.detail {
                    if let r = detail.range(of: "warning: ") { detail = String(detail[r.upperBound...]) }
                    if let r = detail.range(of: "error: ") { detail = String(detail[r.upperBound...]) }
                    if let r = detail.range(of: " ^~") { detail = String(detail[..<r.lowerBound]) }
                    message = detail
                }
                let key = "\(step.signature):\(notice.startingLineNumber):\(notice.startingColumnNumber):\(issueType)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                let path: String? = {
                    let doc = step.documentURL.replacingOccurrences(of: "file://", with: "")
                    return doc.isEmpty ? nil : doc
                }()

                result.append(Issue(
                    type: issueType,
                    target: extractTargetFromSignature(step.signature),
                    project: extractProjectFromSignature(step.signature),
                    title: step.title,
                    signature: step.signature,
                    step_type: stepTypeString(from: step.signature),
                    path: path,
                    message: message.flatMap { $0.count > 1000 ? String($0.prefix(1000)) + "..." : $0 },
                    starting_line: Int(notice.startingLineNumber),
                    ending_line: Int(notice.endingLineNumber),
                    starting_column: Int(notice.startingColumnNumber),
                    ending_column: Int(notice.endingColumnNumber)
                ))
            }
        }
        return result
    }

    // MARK: - Files

    private func extractFiles(from steps: [BuildStep]) -> [File] {
        steps.compactMap { step -> File? in
            guard step.type == .detail else { return nil }
            let fileType: String
            switch step.detailStepType {
            case .swiftCompilation: fileType = "swift"
            case .cCompilation: fileType = "c"
            default:
                if step.signature.hasPrefix("SwiftCompile ") { fileType = "swift" }
                else { return nil }
            }
            guard !step.title.hasPrefix("Emit") else { return nil }

            let doc = step.documentURL.replacingOccurrences(of: "file://", with: "")
            guard !doc.isEmpty else { return nil }

            return File(
                type: fileType,
                target: extractTargetFromSignature(step.signature),
                project: extractProjectFromSignature(step.signature),
                path: doc,
                compilation_duration: Int((step.compilationDuration * 1000).rounded(.up))
            )
        }
    }

    // MARK: - Cache Analysis

    private func analyzeCacheableTasks(
        buildSteps: [BuildStep],
        casReader: CASMetadataReader
    ) async throws -> [CacheableTask] {
        var keyStatuses = [String: (taskType: String, hasQuery: Bool, hasMaterialize: Bool, hasUpload: Bool, isMiss: Bool)]()
        var keyDescriptions = [String: String]()
        var keyNodeIDs = [String: Set<String>]()

        for step in buildSteps {
            guard step.title.contains("Swift caching") || step.title.contains("Clang caching") else { continue }
            let taskType = step.title.contains("Swift caching") ? "swift" : "clang"
            guard let key = extractCacheKey(from: step.title) else { continue }

            let operation: String?
            if step.title.contains("query key") { operation = "query" }
            else if step.title.contains("materialize key") { operation = "materialize" }
            else if step.title.contains("upload key") { operation = "upload" }
            else { operation = nil }

            guard let op = operation else { continue }

            let isMiss = step.notes?.contains { $0.title == "cache key query miss" } ?? false
            var status = keyStatuses[key] ?? (taskType: taskType, hasQuery: false, hasMaterialize: false, hasUpload: false, isMiss: false)
            status.taskType = taskType
            if op == "query" { status.hasQuery = true }
            if op == "materialize" { status.hasMaterialize = true }
            if op == "upload" { status.hasUpload = true }
            if isMiss { status.isMiss = true }
            keyStatuses[key] = status
        }

        for step in buildSteps {
            guard let notes = step.notes else { continue }
            for note in notes {
                if let key = extractCacheKeyFromNote(note.title) {
                    keyDescriptions[key] = step.title
                }
            }
            let cacheKey = extractCacheKey(from: step.title) ?? notes.compactMap({ extractCacheKeyFromNote($0.title) }).first
            guard let ck = cacheKey else { continue }
            for note in notes {
                if let nodeID = extractNodeIDFromNote(note.title) {
                    keyNodeIDs[ck, default: []].insert(nodeID)
                } else if let nodeID = extractNodeIDFromUploadNote(note.title) {
                    keyNodeIDs[ck, default: []].insert(nodeID)
                }
            }
        }

        let descriptions = keyDescriptions
        let nodeIDs = keyNodeIDs

        return try await Array(keyStatuses).concurrentMap(maxConcurrentTasks: 50) { (key, status) in
            let cacheStatus: String
            if status.isMiss { cacheStatus = "miss" }
            else if status.hasQuery { cacheStatus = "hit_remote" }
            else { cacheStatus = "hit_local" }

            let readDuration: Double?
            if cacheStatus == "hit_remote" || cacheStatus == "miss" {
                readDuration = await casReader.readKeyValueMetadata(key: key, operationType: "read")?.duration
            } else {
                readDuration = nil
            }

            let writeDuration: Double?
            if status.hasUpload {
                writeDuration = await casReader.readKeyValueMetadata(key: key, operationType: "write")?.duration
            } else {
                writeDuration = nil
            }

            return CacheableTask(
                type: status.taskType,
                status: cacheStatus,
                key: key,
                read_duration: readDuration,
                write_duration: writeDuration,
                description: descriptions[key],
                cas_output_node_ids: Array(nodeIDs[key] ?? [])
            )
        }
    }

    // MARK: - CAS Outputs

    private func analyzeCASOutputs(
        from buildSteps: [BuildStep],
        casReader: CASMetadataReader
    ) async throws -> [CASOutput] {
        var downloads = [(nodeID: String, type: String)]()
        var uploads = [(nodeID: String, type: String)]()

        for step in buildSteps {
            guard let notes = step.notes else { continue }
            for note in notes {
                if let meta = extractNodeIDAndTypeFromNote(note.title) {
                    downloads.append(meta)
                }
            }
            if step.title.contains("Swift caching upload key") {
                for note in notes {
                    if note.title.hasPrefix("uploaded CAS output "),
                       let meta = extractNodeIDAndTypeFromUploadNote(note.title)
                    {
                        uploads.append(meta)
                    }
                }
            }
        }

        var uniqueDownloads = [(nodeID: String, type: String)]()
        var seenDownloads = Set<String>()
        for meta in downloads {
            guard !seenDownloads.contains(meta.nodeID) else { continue }
            seenDownloads.insert(meta.nodeID)
            uniqueDownloads.append(meta)
        }

        var uniqueUploads = [(nodeID: String, type: String)]()
        var seenUploads = Set<String>()
        for meta in uploads {
            guard !seenUploads.contains(meta.nodeID) else { continue }
            seenUploads.insert(meta.nodeID)
            uniqueUploads.append(meta)
        }

        let allItems: [(nodeID: String, type: String, operation: String)] =
            uniqueDownloads.map { ($0.nodeID, $0.type, "download") } +
            uniqueUploads.map { ($0.nodeID, $0.type, "upload") }

        return try await allItems.concurrentCompactMap(maxConcurrentTasks: 50) { item in
            await createCASOutput(nodeID: item.nodeID, type: item.type, operation: item.operation, casReader: casReader)
        }
    }

    private func createCASOutput(
        nodeID: String,
        type: String,
        operation: String,
        casReader: CASMetadataReader
    ) async -> CASOutput? {
        guard let checksum = await casReader.readChecksum(nodeID: nodeID),
              let metadata = await casReader.readOutputMetadata(checksum: checksum)
        else { return nil }
        return CASOutput(
            node_id: nodeID,
            checksum: checksum,
            size: metadata.size,
            duration: metadata.duration,
            compressed_size: metadata.compressedSize,
            operation: operation,
            type: type
        )
    }

    // MARK: - Regex Helpers

    private func extractCacheKey(from title: String) -> String? {
        if title.contains("query key") || title.contains("materialize key") {
            return extractWithPattern("\\[\"([^\"]+)\"\\]", from: title)
        } else if title.contains("upload key") {
            return extractWithPattern("upload key ([^\\s]+)", from: title)
        }
        return nil
    }

    private func extractCacheKeyFromNote(_ noteTitle: String) -> String? {
        let pattern = "(?i)(?:local cache found for key:|local cache miss for key:)\\s+(0~[A-Za-z0-9+/_=-]+)"
        return extractWithPattern(pattern, from: noteTitle)
    }

    private func extractNodeIDFromNote(_ noteTitle: String) -> String? {
        extractWithPattern("CAS output [^\\s]+: (0~[A-Za-z0-9+/_=-]+)", from: noteTitle)
    }

    private func extractNodeIDFromUploadNote(_ noteTitle: String) -> String? {
        extractWithPattern("uploaded CAS output [^\\s]+: (0~[A-Za-z0-9+/_=-]+)", from: noteTitle)
    }

    private func extractNodeIDAndTypeFromNote(_ noteTitle: String) -> (nodeID: String, type: String)? {
        let pattern = "(?i)using CAS output ([^\\s]+): (0~[A-Za-z0-9+/_=-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: noteTitle, range: NSRange(noteTitle.startIndex..., in: noteTitle)),
              let typeRange = Range(match.range(at: 1), in: noteTitle),
              let nodeIDRange = Range(match.range(at: 2), in: noteTitle)
        else { return nil }
        return (nodeID: String(noteTitle[nodeIDRange]), type: String(noteTitle[typeRange]))
    }

    private func extractNodeIDAndTypeFromUploadNote(_ noteTitle: String) -> (nodeID: String, type: String)? {
        let pattern = "uploaded CAS output ([^\\s]+): (0~[A-Za-z0-9+/_=-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: noteTitle, range: NSRange(noteTitle.startIndex..., in: noteTitle)),
              let typeRange = Range(match.range(at: 1), in: noteTitle),
              let nodeIDRange = Range(match.range(at: 2), in: noteTitle)
        else { return nil }
        return (nodeID: String(noteTitle[nodeIDRange]), type: String(noteTitle[typeRange]))
    }

    private func extractWithPattern(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private func extractTargetFromSignature(_ signature: String) -> String {
        extractWithPattern("in target '([^']+)'", from: signature) ?? ""
    }

    private func extractProjectFromSignature(_ signature: String) -> String {
        extractWithPattern("from project '([^']+)'", from: signature) ?? ""
    }

    private func extractProject(from steps: [BuildStep]) -> [(project: String, Void)] {
        steps.map { (project: extractProjectFromSignature($0.signature), ()) }
    }

    private func stepTypeString(from signature: String) -> String {
        if signature.hasPrefix("CompileC ") { return "c_compilation" }
        if signature.hasPrefix("SwiftCompile ") || signature.hasPrefix("CompileSwift ") || signature.hasPrefix("CompileSwiftSources ") { return "swift_compilation" }
        if signature.hasPrefix("PhaseScriptExecution ") { return "script_execution" }
        if signature.hasPrefix("CreateStaticLibrary ") || signature.hasPrefix("Libtool ") { return "create_static_library" }
        if signature.hasPrefix("Ld ") || signature.hasPrefix("Link ") { return "linker" }
        if signature.hasPrefix("CopySwiftLibs ") { return "copy_swift_libs" }
        if signature.hasPrefix("CompileAssetCatalog ") { return "compile_assets_catalog" }
        if signature.hasPrefix("CompileStoryboard ") { return "compile_storyboard" }
        if signature.hasPrefix("WriteAuxiliaryFile ") { return "write_auxiliary_file" }
        if signature.hasPrefix("LinkStoryboards ") { return "link_storyboards" }
        if signature.hasPrefix("CopyResourceFile ") || signature.hasPrefix("CpResource ") { return "copy_resource_file" }
        if signature.hasPrefix("MergeSwiftModule ") { return "merge_swift_module" }
        if signature.hasPrefix("CompileXIB ") { return "xib_compilation" }
        if signature.hasPrefix("PrecompileBridgingHeader ") { return "precompile_bridging_header" }
        if signature.hasPrefix("ValidateEmbeddedBinary ") { return "validate_embedded_binary" }
        if signature.hasPrefix("Validate ") { return "validate" }
        return "other"
    }
}
