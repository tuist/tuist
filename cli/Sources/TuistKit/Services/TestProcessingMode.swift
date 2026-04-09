import ArgumentParser

public enum TestProcessingMode: String, Sendable, CaseIterable, ExpressibleByArgument {
    case local
    case remote
}
