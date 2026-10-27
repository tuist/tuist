import AppIntents

@available(iOS 17.0, *)
public struct IntentsFrameworkPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] { [] }
}
