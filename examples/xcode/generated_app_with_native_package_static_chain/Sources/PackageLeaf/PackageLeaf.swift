import PackageFeature

public enum PackageLeaf {
    public static func value() -> Int32 {
        PackageFeature.value()
    }
}
