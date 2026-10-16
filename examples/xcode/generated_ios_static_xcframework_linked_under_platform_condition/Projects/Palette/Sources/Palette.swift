import Renderer
import Tokens

public enum Palette {
    public static func version() -> Int32 {
        Renderer.version() + Int32(Tokens.spacing)
    }
}
