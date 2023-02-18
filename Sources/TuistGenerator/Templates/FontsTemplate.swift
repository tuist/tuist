extension SynthesizedResourceInterfaceTemplates {
    static let fontsTemplate = """
    // swiftlint:disable all
    // swift-format-ignore-file
    // swiftformat:disable all
    // Generated using tuist — https://github.com/tuist/tuist

    {% if families %}
    {% set accessModifier %}{% if param.publicAccess %}public{% else %}internal{% endif %}{% endset %}
    {% set fontType %}{{param.name}}FontConvertible{% endset %}
    #if os(macOS)
      import AppKit.NSFont
    #elseif os(iOS) || os(tvOS) || os(watchOS)
      import UIKit.UIFont
    #endif

    // swiftlint:disable superfluous_disable_command
    // swiftlint:disable file_length

    // MARK: - Fonts

    // swiftlint:disable identifier_name line_length type_body_length
    {% macro transformPath path %}{% filter removeNewlines %}
      {% if param.preservePath %}
        {{path}}
      {% else %}
        {{path|basename}}
      {% endif %}
    {% endfilter %}{% endmacro %}
    {{accessModifier}} enum {{param.name}}FontFamily {
      {% for family in families %}
      {{accessModifier}} enum {{family.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% for font in family.fonts %}
        {{accessModifier}} static let {{font.style|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}} = {{fontType}}(name: "{{font.name}}", family: "{{family.name}}", path: "{% call transformPath font.path %}")
        {% endfor %}
        {{accessModifier}} static let all: [{{fontType}}] = [{% for font in family.fonts %}{{font.style|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}}{{ ", " if not forloop.last }}{% endfor %}]
      }
      {% endfor %}
      {{accessModifier}} static let allCustomFonts: [{{fontType}}] = [{% for family in families %}{{family.name|swiftIdentifier:"pretty"|escapeReservedKeywords}}.all{{ ", " if not forloop.last }}{% endfor %}].flatMap { $0 }
      {{accessModifier}} static func registerAllCustomFonts() {
        allCustomFonts.forEach { $0.register() }
      }
    }
    // swiftlint:enable identifier_name line_length type_body_length

    // MARK: - Implementation Details

    {{accessModifier}} struct {{fontType}} {
      {{accessModifier}} let name: String
      {{accessModifier}} let family: String
      {{accessModifier}} let path: String

      #if os(macOS)
      {{accessModifier}} typealias Font = NSFont
      #elseif os(iOS) || os(tvOS) || os(watchOS)
      {{accessModifier}} typealias Font = UIFont
      #endif

      {{accessModifier}} func font(size: CGFloat) -> Font {
        guard let font = Font(font: self, size: size) else {
          fatalError("Unable to initialize font '\\(name)' (\\(family))")
        }
        return font
      }

      {{accessModifier}} func register() {
        // swiftlint:disable:next conditional_returns_on_newline
        guard let url = url else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      }

      fileprivate var url: URL? {
        // swiftlint:disable:next implicit_return
        {% if param.lookupFunction %}
        return {{param.lookupFunction}}(name, family, path)
        {% else %}
        return {{param.bundle|default:"BundleToken.bundle"}}.url(forResource: path, withExtension: nil)
        {% endif %}
      }
    }

    {{accessModifier}} extension {{fontType}}.Font {
      convenience init?(font: {{fontType}}, size: CGFloat) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if !UIFont.fontNames(forFamilyName: font.family).contains(font.name) {
          font.register()
        }
        #elseif os(macOS)
        if let url = font.url, CTFontManagerGetScopeForURL(url as CFURL) == .none {
          font.register()
        }
        #endif

        self.init(name: font.name, size: size)
      }
    }
    {% if not param.bundle and not param.lookupFunction %}

    // swiftlint:disable convenience_type
    private final class BundleToken {
      static let bundle: Bundle = {
        Bundle(for: BundleToken.self)
      }()
    }
    // swiftlint:enable convenience_type
    {% endif %}
    {% else %}
    // No fonts found
    {% endif %}
    // swiftlint:enable all
    // swiftformat:enable all

    """
}
