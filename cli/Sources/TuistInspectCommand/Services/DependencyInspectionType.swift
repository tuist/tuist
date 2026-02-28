#if os(macOS)
    import ArgumentParser

    public enum DependencyInspectionType: String, CaseIterable, ExpressibleByArgument {
        case implicit
        case redundant

        public var defaultValueDescription: String {
            "implicit, redundant"
        }
    }
#endif
