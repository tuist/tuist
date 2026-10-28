/// Exposes the parsed project path so configuration and reporting use the same directory as command execution.
public protocol ProjectPathProviding {
    var path: String? { get }
}
