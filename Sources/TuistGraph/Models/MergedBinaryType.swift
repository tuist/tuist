/// Represents the different options to configure a target for mergeable libraries
///
/// https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries
public enum MergedBinaryType: Equatable, Codable {
    /// Target is never going to merge available dependencies
    case disabled

    /// Target is going to merge direct target dependencies (just the ones declared as part of it's project). With this build
    /// setting,
    /// Xcode treats mergeable dependencies like normal dynamic libraries in debug builds,
    /// but performs steps in release mode to automatically handle merging for **direct dependencies**
    ///
    /// A direct dependency is a library that meets two criteria:
    /// - The library is listed in your target’s Link Binary with Libraries build phase.
    /// - The library is the product of another target in your project.
    case automatic

    /// Target is going to merge direct and specified dependencies that are not part of the project. The set of dependencies
    /// is going to reflect the list of precompiled dynamic dependencies you want to merge as part of the target. These binaries
    /// must be compiled with `MAKE_MERGEABLE` flag set to true
    ///
    /// In some cases, you may want to manually configure merging between your app or framework target and dependent libraries.
    /// For example, you might not want to automatically merge dependencies that you share between an app and an app extension
    /// if you’re concerned about the app extension’s binary size. To set up manual merging, configure your app or framework
    /// target,
    /// then configure your dependent libraries.
    ///
    /// In your app or framework target, add the flag `mergedBinaryType` and set it to manual. After you add that setting to your
    /// target:
    /// - In release builds, Xcode merges the products of any of its direct dependencies which have
    /// MAKE_MERGEABLE enabled using the linker flags -merge_framework, -merge-l and so on.
    /// - In debug builds, Xcode links any of your target’s direct dependencies which have MERGEABLE_LIBRARY
    ///  enabled, but not MAKE_MERGEABLE with the linker flags -reexport_framework, -reexport-l, and so on.
    /// - Xcode uses normal linking for targets that don’t have MERGEABLE_LIBRARY enabled. This is the same linking
    /// that Xcode uses for static libraries, or dynamic libraries that aren’t mergeable.
    case manual(mergeableDependencies: Set<String>)
}
