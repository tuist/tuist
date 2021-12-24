//
//  ColorizeSwift.swift
//  ColorizeSwift
//
//  Created by Michał Tynior on 31/03/16.
//  Copyright © 2016 Michal Tynior. All rights reserved.
//
// swiftlint:disable type_body_length
// swiftlint:disable identifier_name
import Foundation

public typealias TerminalStyleCode = (open: String, close: String)

public enum TerminalStyle {
    public static let bold: TerminalStyleCode = ("\u{001B}[1m", "\u{001B}[22m")
    public static let dim: TerminalStyleCode = ("\u{001B}[2m", "\u{001B}[22m")
    public static let italic: TerminalStyleCode = ("\u{001B}[3m", "\u{001B}[23m")
    public static let underline: TerminalStyleCode = ("\u{001B}[4m", "\u{001B}[24m")
    public static let blink: TerminalStyleCode = ("\u{001B}[5m", "\u{001B}[25m")
    public static let reverse: TerminalStyleCode = ("\u{001B}[7m", "\u{001B}[27m")
    public static let hidden: TerminalStyleCode = ("\u{001B}[8m", "\u{001B}[28m")
    public static let strikethrough: TerminalStyleCode = ("\u{001B}[9m", "\u{001B}[29m")
    public static let reset: TerminalStyleCode = ("\u{001B}[0m", "")

    public static let black: TerminalStyleCode = ("\u{001B}[30m", "\u{001B}[0m")
    public static let red: TerminalStyleCode = ("\u{001B}[31m", "\u{001B}[0m")
    public static let green: TerminalStyleCode = ("\u{001B}[32m", "\u{001B}[0m")
    public static let yellow: TerminalStyleCode = ("\u{001B}[33m", "\u{001B}[0m")
    public static let blue: TerminalStyleCode = ("\u{001B}[34m", "\u{001B}[0m")
    public static let magenta: TerminalStyleCode = ("\u{001B}[35m", "\u{001B}[0m")
    public static let cyan: TerminalStyleCode = ("\u{001B}[36m", "\u{001B}[0m")
    public static let lightGray: TerminalStyleCode = ("\u{001B}[37m", "\u{001B}[0m")
    public static let darkGray: TerminalStyleCode = ("\u{001B}[90m", "\u{001B}[0m")
    public static let lightRed: TerminalStyleCode = ("\u{001B}[91m", "\u{001B}[0m")
    public static let lightGreen: TerminalStyleCode = ("\u{001B}[92m", "\u{001B}[0m")
    public static let lightYellow: TerminalStyleCode = ("\u{001B}[93m", "\u{001B}[0m")
    public static let lightBlue: TerminalStyleCode = ("\u{001B}[94m", "\u{001B}[0m")
    public static let lightMagenta: TerminalStyleCode = ("\u{001B}[95m", "\u{001B}[0m")
    public static let lightCyan: TerminalStyleCode = ("\u{001B}[96m", "\u{001B}[0m")
    public static let white: TerminalStyleCode = ("\u{001B}[97m", "\u{001B}[0m")

    public static let onBlack: TerminalStyleCode = ("\u{001B}[40m", "\u{001B}[0m")
    public static let onRed: TerminalStyleCode = ("\u{001B}[41m", "\u{001B}[0m")
    public static let onGreen: TerminalStyleCode = ("\u{001B}[42m", "\u{001B}[0m")
    public static let onYellow: TerminalStyleCode = ("\u{001B}[43m", "\u{001B}[0m")
    public static let onBlue: TerminalStyleCode = ("\u{001B}[44m", "\u{001B}[0m")
    public static let onMagenta: TerminalStyleCode = ("\u{001B}[45m", "\u{001B}[0m")
    public static let onCyan: TerminalStyleCode = ("\u{001B}[46m", "\u{001B}[0m")
    public static let onLightGray: TerminalStyleCode = ("\u{001B}[47m", "\u{001B}[0m")
    public static let onDarkGray: TerminalStyleCode = ("\u{001B}[100m", "\u{001B}[0m")
    public static let onLightRed: TerminalStyleCode = ("\u{001B}[101m", "\u{001B}[0m")
    public static let onLightGreen: TerminalStyleCode = ("\u{001B}[102m", "\u{001B}[0m")
    public static let onLightYellow: TerminalStyleCode = ("\u{001B}[103m", "\u{001B}[0m")
    public static let onLightBlue: TerminalStyleCode = ("\u{001B}[104m", "\u{001B}[0m")
    public static let onLightMagenta: TerminalStyleCode = ("\u{001B}[105m", "\u{001B}[0m")
    public static let onLightCyan: TerminalStyleCode = ("\u{001B}[106m", "\u{001B}[0m")
    public static let onWhite: TerminalStyleCode = ("\u{001B}[107m", "\u{001B}[0m")
}

extension String {
    /// Enable/disable colorization
    public static var isColorizationEnabled = true

    public func bold() -> String {
        applyStyle(TerminalStyle.bold)
    }

    public func dim() -> String {
        applyStyle(TerminalStyle.dim)
    }

    public func italic() -> String {
        applyStyle(TerminalStyle.italic)
    }

    public func underline() -> String {
        applyStyle(TerminalStyle.underline)
    }

    public func blink() -> String {
        applyStyle(TerminalStyle.blink)
    }

    public func reverse() -> String {
        applyStyle(TerminalStyle.reverse)
    }

    public func hidden() -> String {
        applyStyle(TerminalStyle.hidden)
    }

    public func strikethrough() -> String {
        applyStyle(TerminalStyle.strikethrough)
    }

    public func reset() -> String {
        guard String.isColorizationEnabled else { return self }
        return "\u{001B}[0m" + self
    }

    public func foregroundColor(_ color: TerminalColor) -> String {
        applyStyle(color.foregroundStyleCode())
    }

    public func backgroundColor(_ color: TerminalColor) -> String {
        applyStyle(color.backgroundStyleCode())
    }

    public func colorize(_ foreground: TerminalColor, background: TerminalColor) -> String {
        applyStyle(foreground.foregroundStyleCode()).applyStyle(background.backgroundStyleCode())
    }

    private func applyStyle(_ codeStyle: TerminalStyleCode) -> String {
        guard String.isColorizationEnabled else { return self }
        let str = replacingOccurrences(of: TerminalStyle.reset.open, with: TerminalStyle.reset.open + codeStyle.open)

        return codeStyle.open + str + TerminalStyle.reset.open
    }
}

extension String {
    public func black() -> String {
        applyStyle(TerminalStyle.black)
    }

    public func red() -> String {
        applyStyle(TerminalStyle.red)
    }

    public func green() -> String {
        applyStyle(TerminalStyle.green)
    }

    public func yellow() -> String {
        applyStyle(TerminalStyle.yellow)
    }

    public func blue() -> String {
        applyStyle(TerminalStyle.blue)
    }

    public func magenta() -> String {
        applyStyle(TerminalStyle.magenta)
    }

    public func cyan() -> String {
        applyStyle(TerminalStyle.cyan)
    }

    public func lightGray() -> String {
        applyStyle(TerminalStyle.lightGray)
    }

    public func darkGray() -> String {
        applyStyle(TerminalStyle.darkGray)
    }

    public func lightRed() -> String {
        applyStyle(TerminalStyle.lightRed)
    }

    public func lightGreen() -> String {
        applyStyle(TerminalStyle.lightGreen)
    }

    public func lightYellow() -> String {
        applyStyle(TerminalStyle.lightYellow)
    }

    public func lightBlue() -> String {
        applyStyle(TerminalStyle.lightBlue)
    }

    public func lightMagenta() -> String {
        applyStyle(TerminalStyle.lightMagenta)
    }

    public func lightCyan() -> String {
        applyStyle(TerminalStyle.lightCyan)
    }

    public func white() -> String {
        applyStyle(TerminalStyle.white)
    }

    public func onBlack() -> String {
        applyStyle(TerminalStyle.onBlack)
    }

    public func onRed() -> String {
        applyStyle(TerminalStyle.onRed)
    }

    public func onGreen() -> String {
        applyStyle(TerminalStyle.onGreen)
    }

    public func onYellow() -> String {
        applyStyle(TerminalStyle.onYellow)
    }

    public func onBlue() -> String {
        applyStyle(TerminalStyle.onBlue)
    }

    public func onMagenta() -> String {
        applyStyle(TerminalStyle.onMagenta)
    }

    public func onCyan() -> String {
        applyStyle(TerminalStyle.onCyan)
    }

    public func onLightGray() -> String {
        applyStyle(TerminalStyle.onLightGray)
    }

    public func onDarkGray() -> String {
        applyStyle(TerminalStyle.onDarkGray)
    }

    public func onLightRed() -> String {
        applyStyle(TerminalStyle.onLightRed)
    }

    public func onLightGreen() -> String {
        applyStyle(TerminalStyle.onLightGreen)
    }

    public func onLightYellow() -> String {
        applyStyle(TerminalStyle.onLightYellow)
    }

    public func onLightBlue() -> String {
        applyStyle(TerminalStyle.onLightBlue)
    }

    public func onLightMagenta() -> String {
        applyStyle(TerminalStyle.onLightMagenta)
    }

    public func onLightCyan() -> String {
        applyStyle(TerminalStyle.onLightCyan)
    }

    public func onWhite() -> String {
        applyStyle(TerminalStyle.onWhite)
    }
}

// https://jonasjacek.github.io/colors/
public enum TerminalColor: UInt8 {
    case black = 0
    case maroon
    case green
    case olive
    case navy
    case purple
    case teal
    case silver
    case grey
    case red
    case lime
    case yellow
    case blue
    case fuchsia
    case aqua
    case white
    case grey0
    case navyBlue
    case darkBlue
    case blue3
    case blue3_2
    case blue1
    case darkGreen
    case deepSkyBlue4
    case deepSkyBlue4_2
    case deepSkyBlue4_3
    case dodgerBlue3
    case dodgerBlue2
    case green4
    case springGreen4
    case turquoise4
    case deepSkyBlue3
    case deepSkyBlue3_2
    case dodgerBlue1
    case green3
    case springGreen3
    case darkCyan
    case lightSeaGreen
    case deepSkyBlue2
    case deepSkyBlue1
    case green3_2
    case springGreen3_2
    case springGreen2
    case cyan3
    case darkTurquoise
    case turquoise2
    case green1
    case springGreen2_2
    case springGreen1
    case mediumSpringGreen
    case cyan2
    case cyan1
    case darkRed
    case deepPink4
    case purple4
    case purple4_2
    case purple3
    case blueViolet
    case orange4
    case grey37
    case mediumPurple4
    case slateBlue3
    case slateBlue3_2
    case royalBlue1
    case chartreuse4
    case darkSeaGreen4
    case paleTurquoise4
    case steelBlue
    case steelBlue3
    case cornflowerBlue
    case chartreuse3
    case darkSeaGreen4_2
    case cadetBlue
    case cadetBlue_2
    case skyBlue3
    case steelBlue1
    case chartreuse3_2
    case paleGreen3
    case seaGreen3
    case aquamarine3
    case mediumTurquoise
    case steelBlue1_2
    case chartreuse2
    case seaGreen2
    case seaGreen1
    case seaGreen1_2
    case aquamarine1
    case darkSlateGray2
    case darkRed_2
    case deepPink4_2
    case darkMagenta
    case darkMagenta_2
    case darkViolet
    case purple_2
    case orange4_2
    case lightPink4
    case plum4
    case mediumPurple3
    case mediumPurple3_2
    case slateBlue1
    case yellow4
    case wheat4
    case grey53
    case lightSlateGrey
    case mediumPurple
    case lightSlateBlue
    case yellow4_2
    case darkOliveGreen3
    case darkSeaGreen
    case lightSkyBlue3
    case lightSkyBlue3_2
    case skyBlue2
    case chartreuse2_2
    case darkOliveGreen3_2
    case paleGreen3_2
    case darkSeaGreen3
    case darkSlateGray3
    case skyBlue1
    case chartreuse1
    case lightGreen
    case lightGreen_2
    case paleGreen1
    case aquamarine1_2
    case darkSlateGray1
    case red3
    case deepPink4_3
    case mediumVioletRed
    case magenta3
    case darkViolet_2
    case purple_3
    case darkOrange3
    case indianRed
    case hotPink3
    case mediumOrchid3
    case mediumOrchid
    case mediumPurple2
    case darkGoldenrod
    case lightSalmon3
    case rosyBrown
    case grey63
    case mediumPurple2_2
    case mediumPurple1
    case gold3
    case darkKhaki
    case navajoWhite3
    case grey69
    case lightSteelBlue3
    case lightSteelBlue
    case yellow3
    case darkOliveGreen3_3
    case darkSeaGreen3_2
    case darkSeaGreen2
    case lightCyan3
    case lightSkyBlue1
    case greenYellow
    case darkOliveGreen2
    case paleGreen1_2
    case darkSeaGreen2_2
    case darkSeaGreen1
    case paleTurquoise1
    case red3_2
    case deepPink3
    case deepPink3_2
    case magenta3_2
    case magenta3_3
    case magenta2
    case darkOrange3_2
    case indianRed_2
    case hotPink3_2
    case hotPink2
    case orchid
    case mediumOrchid1
    case orange3
    case lightSalmon3_2
    case lightPink3
    case pink3
    case plum3
    case violet
    case gold3_2
    case lightGoldenrod3
    case tan
    case mistyRose3
    case thistle3
    case plum2
    case yellow3_2
    case khaki3
    case lightGoldenrod2
    case lightYellow3
    case grey84
    case lightSteelBlue1
    case yellow2
    case darkOliveGreen1
    case darkOliveGreen1_2
    case darkSeaGreen1_2
    case honeydew2
    case lightCyan1
    case red1
    case deepPink2
    case deepPink1
    case deepPink1_2
    case magenta2_2
    case magenta1
    case orangeRed1
    case indianRed1
    case indianRed1_2
    case hotPink
    case hotPink_2
    case mediumOrchid1_2
    case darkOrange
    case salmon1
    case lightCoral
    case paleVioletRed1
    case orchid2
    case orchid1
    case orange1
    case sandyBrown
    case lightSalmon1
    case lightPink1
    case pink1
    case plum1
    case gold1
    case lightGoldenrod2_2
    case lightGoldenrod2_3
    case navajoWhite1
    case mistyRose1
    case thistle1
    case yellow1
    case lightGoldenrod1
    case khaki1
    case wheat1
    case cornsilk1
    case grey100
    case grey3
    case grey7
    case grey11
    case grey15
    case grey19
    case grey23
    case grey27
    case grey30
    case grey35
    case grey39
    case grey42
    case grey46
    case grey50
    case grey54
    case grey58
    case grey62
    case grey66
    case grey70
    case grey74
    case grey78
    case grey82
    case grey85
    case grey89
    case grey93

    public func foregroundStyleCode() -> TerminalStyleCode {
        ("\u{001B}[38;5;\(rawValue)m", TerminalStyle.reset.open)
    }

    public func backgroundStyleCode() -> TerminalStyleCode {
        ("\u{001B}[48;5;\(rawValue)m", TerminalStyle.reset.open)
    }
}
