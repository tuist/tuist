import Foundation
import XCLogParser

// MARK: - Output Models

struct ParsedBuildData: Encodable {
    let duration: Int
    let status: String
    let category: String
    let is_ci: Bool
    let macos_version: String
    let xcode_version: String
    let model_identifier: String
    let targets: [ParsedTarget]
    let issues: [ParsedIssue]
    let files: [ParsedFile]
    let cacheable_tasks: [ParsedCacheableTask]
    let cas_outputs: [ParsedCASOutput]
}

struct ParsedTarget: Encodable {
    let name: String
    let project: String
    let build_duration: Int
    let compilation_duration: Int
    let status: String
}

struct ParsedIssue: Encodable {
    let type: String
    let target: String
    let project: String
    let title: String
    let signature: String
    let step_type: String
    let path: String?
    let message: String?
    let starting_line: Int
    let ending_line: Int
    let starting_column: Int
    let ending_column: Int
}

struct ParsedFile: Encodable {
    let type: String
    let target: String
    let project: String
    let path: String
    let compilation_duration: Int
}

struct ParsedCacheableTask: Encodable {
    let type: String
    let status: String
    let key: String
    let read_duration: Double?
    let write_duration: Double?
    let description: String?
    let cas_output_node_ids: [String]
}

struct ParsedCASOutput: Encodable {
    let node_id: String
    let checksum: String
    let size: Int
    let duration: Double
    let compressed_size: Int
    let operation: String
    let type: String?
}

// MARK: - CAS Metadata Stores

struct CASNodeEntry: Decodable {
    let checksum: String
}

struct CASOutputMetadataEntry: Decodable {
    let size: Int
    let duration: Double
    let compressed_size: Int
}

struct KeyValueMetadataEntry: Decodable {
    let duration: Double
}

enum CASMetadataReader {
    static func readChecksum(nodeID: String, casMetadataPath: String) -> String? {
        let nodesDir = (casMetadataPath as NSString).appendingPathComponent("nodes")
        let safeNodeID = nodeID.replacingOccurrences(of: "/", with: "_")
        let path = (nodesDir as NSString).appendingPathComponent("\(safeNodeID).json")
        guard let data = FileManager.default.contents(atPath: path),
              let entry = try? JSONDecoder().decode(CASNodeEntry.self, from: data)
        else { return nil }
        return entry.checksum
    }

    static func readOutputMetadata(checksum: String, casMetadataPath: String) -> CASOutputMetadataEntry? {
        let casDir = (casMetadataPath as NSString).appendingPathComponent("cas")
        let path = (casDir as NSString).appendingPathComponent("\(checksum).json")
        guard let data = FileManager.default.contents(atPath: path),
              let entry = try? JSONDecoder().decode(CASOutputMetadataEntry.self, from: data)
        else { return nil }
        return entry
    }

    static func readKeyValueMetadata(key: String, operationType: String, casMetadataPath: String) -> KeyValueMetadataEntry? {
        let kvDir = (casMetadataPath as NSString).appendingPathComponent("keyvalue")
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
        let path = (kvDir as NSString).appendingPathComponent("\(safeKey)_\(operationType).json")
        guard let data = FileManager.default.contents(atPath: path),
              let entry = try? JSONDecoder().decode(KeyValueMetadataEntry.self, from: data)
        else { return nil }
        return entry
    }
}

// MARK: - Manifest

struct BuildArchiveManifest: Decodable {
    let cache_upload_enabled: Bool
    let macos_version: String
    let model_identifier: String?
    let xcode_version: String?
}

// MARK: - Parser

enum XCActivityLogParser {
    static func parse(
        xcactivitylogPath: String,
        casMetadataPath: String,
        cacheUploadEnabled: Bool,
        manifest: BuildArchiveManifest?
    ) throws -> Data {
        let url = URL(fileURLWithPath: xcactivitylogPath)
        let activityLog = try ActivityParser().parseActivityLogInURL(
            url,
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

        let targets = targetSteps.map { step -> ParsedTarget in
            let subSteps = flattenBuildSteps([step])
            let hasErrors = subSteps.contains { ($0.errors ?? []).contains { $0.severity == 2 } }
            return ParsedTarget(
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
        let cacheableTasks = analyzeCacheableTasks(
            buildSteps: steps,
            casMetadataPath: casMetadataPath
        )
        let casOutputs = analyzeCASOutputs(
            from: steps,
            casMetadataPath: casMetadataPath,
            cacheUploadEnabled: cacheUploadEnabled
        )

        let duration = Int(activityLog.mainSection.timeStoppedRecording * 1000)
            - Int(activityLog.mainSection.timeStartedRecording * 1000)

        let data = ParsedBuildData(
            duration: duration,
            status: errorCount == 0 ? "success" : "failure",
            category: category == .clean ? "clean" : "incremental",
            is_ci: false,
            macos_version: manifest?.macos_version ?? "",
            xcode_version: manifest?.xcode_version ?? "",
            model_identifier: manifest?.model_identifier ?? "",
            targets: targets,
            issues: Array(issues.prefix(1000)),
            files: files,
            cacheable_tasks: cacheableTasks,
            cas_outputs: casOutputs
        )

        return try JSONEncoder().encode(data)
    }

    // MARK: - Build Steps

    private static func flattenBuildSteps(_ steps: [BuildStep]) -> [BuildStep] {
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

    private static func determineCategory(
        steps: [BuildStep],
        targetSteps: [BuildStep],
        activityLog: IDEActivityLog
    ) -> BuildCategory {
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

        let hasCompilationCache = steps.contains {
            $0.title.contains("Swift caching") || $0.title.contains("Clang caching")
        }
        let totalProjectTargetCount = totalTargetCountFromDependencyGraph(activityLog)
        let totalTargets: Int
        if hasCompilationCache, totalProjectTargetCount > targetSteps.count {
            totalTargets = totalProjectTargetCount
        } else {
            totalTargets = targetSteps.count
        }

        return cleanCount > totalTargets / 2 ? .clean : .incremental
    }

    private static func totalTargetCountFromDependencyGraph(_ activityLog: IDEActivityLog) -> Int {
        var names = Set<String>()
        collectDependencyGraphTargets(from: activityLog.mainSection, into: &names)
        return names.count
    }

    private static func collectDependencyGraphTargets(from section: IDEActivityLogSection, into names: inout Set<String>) {
        extractTargetNames(from: section.text, into: &names)
        for message in section.messages {
            extractTargetNames(from: message.title, into: &names)
        }
        for sub in section.subSections {
            collectDependencyGraphTargets(from: sub, into: &names)
        }
    }

    private static func extractTargetNames(from text: String, into names: inout Set<String>) {
        guard text.contains("Target dependency graph") else { return }
        let pattern = "Target '([^']+)' in project"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            if let nameRange = Range(match.range(at: 1), in: text) {
                names.insert(String(text[nameRange]))
            }
        }
    }

    private static func buildTargetIdentifiers(from steps: [BuildStep]) -> [String: String] {
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

    private static func extractIssues(from steps: [BuildStep]) -> [ParsedIssue] {
        var seen = Set<String>()
        var result = [ParsedIssue]()
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

                result.append(ParsedIssue(
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

    private static func extractFiles(from steps: [BuildStep]) -> [ParsedFile] {
        steps.compactMap { step -> ParsedFile? in
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

            return ParsedFile(
                type: fileType,
                target: extractTargetFromSignature(step.signature),
                project: extractProjectFromSignature(step.signature),
                path: doc,
                compilation_duration: Int((step.compilationDuration * 1000).rounded(.up))
            )
        }
    }

    // MARK: - Cache Analysis

    private static func analyzeCacheableTasks(
        buildSteps: [BuildStep],
        casMetadataPath: String
    ) -> [ParsedCacheableTask] {
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

        return keyStatuses.map { key, status in
            let cacheStatus: String
            if status.isMiss { cacheStatus = "miss" }
            else if status.hasQuery { cacheStatus = "hit_remote" }
            else { cacheStatus = "hit_local" }

            let readDuration: Double?
            if cacheStatus == "hit_remote" || cacheStatus == "miss" {
                readDuration = CASMetadataReader.readKeyValueMetadata(key: key, operationType: "read", casMetadataPath: casMetadataPath)?.duration
            } else {
                readDuration = nil
            }

            let writeDuration: Double?
            if status.hasUpload {
                writeDuration = CASMetadataReader.readKeyValueMetadata(key: key, operationType: "write", casMetadataPath: casMetadataPath)?.duration
            } else {
                writeDuration = nil
            }

            return ParsedCacheableTask(
                type: status.taskType,
                status: cacheStatus,
                key: key,
                read_duration: readDuration,
                write_duration: writeDuration,
                description: keyDescriptions[key],
                cas_output_node_ids: Array(keyNodeIDs[key] ?? [])
            )
        }
    }

    // MARK: - CAS Outputs

    private static func analyzeCASOutputs(
        from buildSteps: [BuildStep],
        casMetadataPath: String,
        cacheUploadEnabled: Bool
    ) -> [ParsedCASOutput] {
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
                       let meta = extractNodeIDAndTypeFromUploadNote(note.title) {
                        uploads.append(meta)
                    }
                }
            }
        }

        var results = [ParsedCASOutput]()
        var seenDownloads = Set<String>()
        for meta in downloads {
            guard !seenDownloads.contains(meta.nodeID) else { continue }
            seenDownloads.insert(meta.nodeID)
            if let output = createCASOutput(nodeID: meta.nodeID, type: meta.type, operation: "download", casMetadataPath: casMetadataPath) {
                results.append(output)
            }
        }

        if cacheUploadEnabled {
            var seenUploads = Set<String>()
            for meta in uploads {
                guard !seenUploads.contains(meta.nodeID) else { continue }
                seenUploads.insert(meta.nodeID)
                if let output = createCASOutput(nodeID: meta.nodeID, type: meta.type, operation: "upload", casMetadataPath: casMetadataPath) {
                    results.append(output)
                }
            }
        }

        return results
    }

    private static func createCASOutput(
        nodeID: String,
        type: String,
        operation: String,
        casMetadataPath: String
    ) -> ParsedCASOutput? {
        guard let checksum = CASMetadataReader.readChecksum(nodeID: nodeID, casMetadataPath: casMetadataPath),
              let metadata = CASMetadataReader.readOutputMetadata(checksum: checksum, casMetadataPath: casMetadataPath)
        else { return nil }
        return ParsedCASOutput(
            node_id: nodeID,
            checksum: checksum,
            size: metadata.size,
            duration: metadata.duration,
            compressed_size: metadata.compressed_size,
            operation: operation,
            type: type
        )
    }

    // MARK: - Regex Helpers

    private static func extractCacheKey(from title: String) -> String? {
        if title.contains("query key") || title.contains("materialize key") {
            return extractWithPattern("\\[\"([^\"]+)\"\\]", from: title)
        } else if title.contains("upload key") {
            return extractWithPattern("upload key ([^\\s]+)", from: title)
        }
        return nil
    }

    private static func extractCacheKeyFromNote(_ noteTitle: String) -> String? {
        let pattern = "(?i)(?:local cache found for key:|local cache miss for key:)\\s+(0~[A-Za-z0-9+/_=-]+)"
        return extractWithPattern(pattern, from: noteTitle)
    }

    private static func extractNodeIDFromNote(_ noteTitle: String) -> String? {
        extractWithPattern("CAS output [^\\s]+: (0~[A-Za-z0-9+/_=-]+)", from: noteTitle)
    }

    private static func extractNodeIDFromUploadNote(_ noteTitle: String) -> String? {
        extractWithPattern("uploaded CAS output [^\\s]+: (0~[A-Za-z0-9+/_=-]+)", from: noteTitle)
    }

    private static func extractNodeIDAndTypeFromNote(_ noteTitle: String) -> (nodeID: String, type: String)? {
        let pattern = "(?i)using CAS output ([^\\s]+): (0~[A-Za-z0-9+/_=-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: noteTitle, range: NSRange(noteTitle.startIndex..., in: noteTitle)),
              let typeRange = Range(match.range(at: 1), in: noteTitle),
              let nodeIDRange = Range(match.range(at: 2), in: noteTitle)
        else { return nil }
        return (nodeID: String(noteTitle[nodeIDRange]), type: String(noteTitle[typeRange]))
    }

    private static func extractNodeIDAndTypeFromUploadNote(_ noteTitle: String) -> (nodeID: String, type: String)? {
        let pattern = "uploaded CAS output ([^\\s]+): (0~[A-Za-z0-9+/_=-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: noteTitle, range: NSRange(noteTitle.startIndex..., in: noteTitle)),
              let typeRange = Range(match.range(at: 1), in: noteTitle),
              let nodeIDRange = Range(match.range(at: 2), in: noteTitle)
        else { return nil }
        return (nodeID: String(noteTitle[nodeIDRange]), type: String(noteTitle[typeRange]))
    }

    private static func extractWithPattern(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func extractTargetFromSignature(_ signature: String) -> String {
        extractWithPattern("in target '([^']+)'", from: signature) ?? ""
    }

    private static func extractProjectFromSignature(_ signature: String) -> String {
        extractWithPattern("from project '([^']+)'", from: signature) ?? ""
    }

    private static func extractProject(from steps: [BuildStep]) -> [(project: String, Void)] {
        steps.map { (project: extractProjectFromSignature($0.signature), ()) }
    }

    private static func stepTypeString(from signature: String) -> String {
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

// MARK: - NIF Entry Point

@_cdecl("parse_xcactivitylog")
public func parseXCActivityLog(
    _ pathPtr: UnsafePointer<CChar>,
    _ casMetadataPathPtr: UnsafePointer<CChar>,
    _ cacheUploadEnabled: Int32,
    _ outputPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ outputLen: UnsafeMutablePointer<Int32>
) -> Int32 {
    let path = String(cString: pathPtr)
    let casMetadataPath = String(cString: casMetadataPathPtr)
    let cacheUploadEnabledBool = cacheUploadEnabled != 0

    // Try to read manifest from the archive directory (parent of xcactivitylog dir)
    let archiveDir = (URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()).path
    let manifestPath = (archiveDir as NSString).appendingPathComponent("manifest.json")
    let manifest: BuildArchiveManifest? = {
        guard let data = FileManager.default.contents(atPath: manifestPath) else { return nil }
        return try? JSONDecoder().decode(BuildArchiveManifest.self, from: data)
    }()

    do {
        let jsonData = try XCActivityLogParser.parse(
            xcactivitylogPath: path,
            casMetadataPath: casMetadataPath,
            cacheUploadEnabled: cacheUploadEnabledBool,
            manifest: manifest
        )

        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: jsonData.count)
        jsonData.withUnsafeBytes { rawBytes in
            buffer.initialize(from: rawBytes.bindMemory(to: CChar.self).baseAddress!, count: jsonData.count)
        }
        outputPtr.pointee = buffer
        outputLen.pointee = Int32(jsonData.count)
        return 0
    } catch {
        let errorJSON = "{\"error\": \"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}"
        let data = Array(errorJSON.utf8)
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
        for (i, byte) in data.enumerated() {
            buffer[i] = CChar(bitPattern: byte)
        }
        outputPtr.pointee = buffer
        outputLen.pointee = Int32(data.count)
        return 1
    }
}
