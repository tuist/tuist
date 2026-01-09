import ArgumentParser

enum DependencyInspectionType: String, CaseIterable, ExpressibleByArgument {
    case implicit
    case redundant

    var defaultValueDescription: String {
        "implicit, redundant"
    }
}
