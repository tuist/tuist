@_exported import NativeRendererFFI

public enum NativeRendererKit {
    public static func version() -> Int32 {
        native_renderer_version()
    }
}
