import XcodeProj

extension PBXTarget {
    /// Returns the headers build phase, if any.
    func headersBuildPhase() throws -> PBXHeadersBuildPhase? {
        buildPhases.compactMap { $0 as? PBXHeadersBuildPhase }.first
    }
}
