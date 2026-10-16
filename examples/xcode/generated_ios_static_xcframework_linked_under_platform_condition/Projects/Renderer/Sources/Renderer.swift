import NativeRendererKit

public enum Renderer {
    public static func version() -> Int32 {
        NativeRendererKit.version()
    }
}
