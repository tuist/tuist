import XcodeGraph

extension Target {
    /// CoreData models are typically added to the sources build phase
    /// and Xcode automatically bundles the models.
    /// For static libraries / frameworks however, they don't support resources,
    /// the models could be bundled in a stand alone `.bundle`
    /// as resources.
    ///
    /// e.g.
    /// MyStaticFramework (.staticFramework) -> Includes CoreData models as sources
    /// MyStaticFrameworkResources (.bundle) -> Includes CoreData models as resources
    ///
    /// - Note: Technically, CoreData models can be added a sources build phase in a `.bundle`
    /// but that will result in the `.bundle` having an executable, which is not valid on iOS.
    var shouldCoreDataModelsBeSources: Bool {
        switch product {
        case .stickerPackExtension, .watch2App:
            return false
        case .bundle:
            return isExclusiveTo(.macOS)
        default:
            return true
        }
    }
}
