import Foundation
@_exported @preconcurrency import SQLite

public enum CASOutputsSchema {
    public static let table = Table("cas_outputs")
    public static let key = SQLite.Expression<String>("key")
    public static let size = SQLite.Expression<Int>("size")
    public static let duration = SQLite.Expression<Double>("duration")
    public static let compressedSize = SQLite.Expression<Int>("compressed_size")
    public static let createdAt = SQLite.Expression<Date>("created_at")
}

public enum NodesSchema {
    public static let table = Table("nodes")
    public static let key = SQLite.Expression<String>("key")
    public static let checksum = SQLite.Expression<String>("checksum")
    public static let createdAt = SQLite.Expression<Date>("created_at")
}

public enum KeyValueMetadataSchema {
    public static let table = Table("keyvalue_metadata")
    public static let key = SQLite.Expression<String>("key")
    public static let operationType = SQLite.Expression<String>("operation_type")
    public static let duration = SQLite.Expression<Double>("duration")
    public static let createdAt = SQLite.Expression<Date>("created_at")
}
