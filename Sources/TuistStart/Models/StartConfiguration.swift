import Path

/// The "tuist start" command is designed to be interactive. However,
/// there are environments like acceptance tests or a possible future
/// web-based workflow, where interactivity is not possible.
///
/// This structr allows skipping the interactivity by passing the information
/// in this model.
public enum StartConfiguration: Codable {
    case addToExistingXcodeProjectOrWorkspace(AbsolutePath)
}
