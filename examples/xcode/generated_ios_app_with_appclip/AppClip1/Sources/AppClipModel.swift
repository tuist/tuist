import StaticFramework

final class AppClipModel {
    func makeStaticFrameworkType() -> StaticFrameworkType {
        StaticFrameworkType(name: "AppClip")
    }

    func staticFrameworkTypeIdentifier() -> String {
        StaticFrameworkType.typeIdentifier
    }
}
