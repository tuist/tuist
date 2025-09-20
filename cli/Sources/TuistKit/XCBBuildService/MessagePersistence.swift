import Foundation
import GRDB
import SWBProtocol
import SWBUtil

/// Shared with XCBBuildService
enum Direction { case xcodeToService, serviceToXcode }

protocol MessageObserver {
    func didDecode(direction: Direction, channel: UInt64, length: Int, name: String, message: any Message, payload: [UInt8])
    func didDecodeError(direction: Direction, channel: UInt64, length: Int, error: Error)
}

struct NoopObserver: MessageObserver {
    func didDecode(
        direction _: Direction,
        channel _: UInt64,
        length _: Int,
        name _: String,
        message _: any Message,
        payload _: [UInt8]
    ) {}
    func didDecodeError(direction _: Direction, channel _: UInt64, length _: Int, error _: Error) {}
}

final class SQLiteObserver: MessageObserver {
    private let dbQueue: DatabaseQueue
    private let ts = ISO8601DateFormatter()

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    private func migrate() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts TEXT NOT NULL,
                    direction TEXT NOT NULL,
                    channel INTEGER NOT NULL,
                    length INTEGER NOT NULL,
                    name TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(ts);
                CREATE INDEX IF NOT EXISTS idx_messages_name ON messages(name);

                -- Session
                CREATE TABLE IF NOT EXISTS session_create (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    name TEXT,
                    developer_path TEXT,
                    app_path TEXT,
                    cache_path TEXT,
                    inferior_products_path TEXT,
                    environment_json TEXT
                );
                CREATE TABLE IF NOT EXISTS session_created (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    session_id TEXT,
                    diagnostics_count INTEGER
                );
                CREATE TABLE IF NOT EXISTS session_set_workspace_container (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    session_handle TEXT,
                    container_path TEXT
                );
                CREATE TABLE IF NOT EXISTS session_set_pif (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    session_handle TEXT,
                    pif_length INTEGER
                );
                CREATE TABLE IF NOT EXISTS transfer_session_pif_request (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    session_handle TEXT,
                    workspace_signature TEXT
                );

                -- Build lifecycle
                CREATE TABLE IF NOT EXISTS build_created (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    id INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_start (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    session_handle TEXT,
                    id INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_cancel (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    session_handle TEXT,
                    id INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_operation_started (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    id INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_operation_ended (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    id INTEGER,
                    status INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_progress_updated (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    target_name TEXT,
                    status_message TEXT,
                    percent_complete REAL,
                    show_in_log INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_task_started (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    id INTEGER,
                    target_id INTEGER,
                    parent_id INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_task_ended (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    id INTEGER,
                    status INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_task_uptodate (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    target_id INTEGER,
                    parent_id INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_console_output (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    data BLOB,
                    task_id INTEGER,
                    target_id INTEGER
                );
                CREATE TABLE IF NOT EXISTS build_diagnostic_emitted (
                    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                    kind INTEGER,
                    message TEXT
                );
            """)
        }
    }

    func didDecode(direction: Direction, channel: UInt64, length: Int, name: String, message: any Message, payload _: [UInt8]) {
        let timestamp = ts.string(from: Date())
        let dir = (direction == .xcodeToService) ? "XCODE→SVC" : "SVC→XCODE"
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "INSERT INTO messages (ts, direction, channel, length, name) VALUES (?, ?, ?, ?, ?)",
                    arguments: [timestamp, dir, channel, length, name]
                )
                let messageID = db.lastInsertedRowID

                switch message {
                case let m as CreateSessionRequest:
                    let envJSON = try? String(data: JSONEncoder().encode(m.environment ?? [:]), encoding: .utf8)
                    try db.execute(
                        sql: "INSERT INTO session_create (message_id, name, developer_path, app_path, cache_path, inferior_products_path, environment_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
                        arguments: [
                            messageID,
                            m.name,
                            m.developerPath?.str ?? (m.developerPath2 == nil ? nil : m.developerPath?.str),
                            m.appPath?.str,
                            m.cachePath?.str,
                            m.inferiorProductsPath?.str,
                            envJSON ?? nil,
                        ]
                    )
                case let m as CreateSessionResponse:
                    try db.execute(
                        sql: "INSERT INTO session_created (message_id, session_id, diagnostics_count) VALUES (?, ?, ?)",
                        arguments: [messageID, m.sessionID, m.diagnostics.count]
                    )
                case let m as SetSessionWorkspaceContainerPathRequest:
                    try db.execute(
                        sql: "INSERT INTO session_set_workspace_container (message_id, session_handle, container_path) VALUES (?, ?, ?)",
                        arguments: [messageID, m.sessionHandle, m.containerPath]
                    )
                case let m as SetSessionPIFRequest:
                    try db.execute(
                        sql: "INSERT INTO session_set_pif (message_id, session_handle, pif_length) VALUES (?, ?, ?)",
                        arguments: [messageID, m.sessionHandle, m.pifContents.count]
                    )
                case let m as TransferSessionPIFRequest:
                    try db.execute(
                        sql: "INSERT INTO transfer_session_pif_request (message_id, session_handle, workspace_signature) VALUES (?, ?, ?)",
                        arguments: [messageID, m.sessionHandle, m.workspaceSignature]
                    )
                case let m as BuildCreated:
                    try db.execute(sql: "INSERT INTO build_created (message_id, id) VALUES (?, ?)", arguments: [messageID, m.id])
                case let m as BuildStartRequest:
                    try db.execute(
                        sql: "INSERT INTO build_start (message_id, session_handle, id) VALUES (?, ?, ?)",
                        arguments: [messageID, m.sessionHandle, m.id]
                    )
                case let m as BuildCancelRequest:
                    try db.execute(
                        sql: "INSERT INTO build_cancel (message_id, session_handle, id) VALUES (?, ?, ?)",
                        arguments: [messageID, m.sessionHandle, m.id]
                    )
                case let m as BuildOperationStarted:
                    try db.execute(
                        sql: "INSERT INTO build_operation_started (message_id, id) VALUES (?, ?)",
                        arguments: [messageID, m.id]
                    )
                case let m as BuildOperationEnded:
                    try db.execute(
                        sql: "INSERT INTO build_operation_ended (message_id, id, status) VALUES (?, ?, ?)",
                        arguments: [messageID, m.id, m.status.rawValue]
                    )
                case let m as BuildOperationProgressUpdated:
                    try db.execute(
                        sql: "INSERT INTO build_progress_updated (message_id, target_name, status_message, percent_complete, show_in_log) VALUES (?, ?, ?, ?, ?)",
                        arguments: [messageID, m.targetName, m.statusMessage, m.percentComplete, m.showInLog ? 1 : 0]
                    )
                case let m as BuildOperationTaskStarted:
                    try db.execute(
                        sql: "INSERT INTO build_task_started (message_id, id, target_id, parent_id) VALUES (?, ?, ?, ?)",
                        arguments: [messageID, m.id, m.targetID, m.parentID]
                    )
                case let m as BuildOperationTaskEnded:
                    try db.execute(
                        sql: "INSERT INTO build_task_ended (message_id, id, status) VALUES (?, ?, ?)",
                        arguments: [messageID, m.id, m.status.rawValue]
                    )
                case let m as BuildOperationTaskUpToDate:
                    try db.execute(
                        sql: "INSERT INTO build_task_uptodate (message_id, target_id, parent_id) VALUES (?, ?, ?)",
                        arguments: [messageID, m.targetID, m.parentID]
                    )
                case let m as BuildOperationConsoleOutputEmitted:
                    try db.execute(
                        sql: "INSERT INTO build_console_output (message_id, data, task_id, target_id) VALUES (?, ?, ?, ?)",
                        arguments: [messageID, Data(m.data), m.taskID, m.targetID]
                    )
                case let m as BuildOperationDiagnosticEmitted:
                    try db.execute(
                        sql: "INSERT INTO build_diagnostic_emitted (message_id, kind, message) VALUES (?, ?, ?)",
                        arguments: [messageID, m.kind.rawValue, m.message]
                    )
                default:
                    break
                }
            }
        } catch {
            // Swallow DB errors to avoid impacting the protocol
        }
    }

    func didDecodeError(direction _: Direction, channel _: UInt64, length _: Int, error _: Error) {
        // No-op; could persist errors in a separate table if desired
    }
}
