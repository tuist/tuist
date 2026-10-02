import Canvas
import Palette

public enum Feature {
    public static func version() -> Int32 {
        Palette.version() + Canvas.version()
    }
}
