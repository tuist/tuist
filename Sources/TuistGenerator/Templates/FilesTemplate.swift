extension SynthesizedResourceInterfaceTemplates {
    static let filesTemplate = """
    // swiftlint:disable all
    // swift-format-ignore-file
    // swiftformat:disable all
    // Generated using tuist — https://github.com/tuist/tuist

    {% if groups.count > 0 %}
    {% set enumName %}{{param.enumName|default:"Files"}}{% endset %}
    {% set useExt %}{% if param.useExtension|default:"true" %}true{% endif %}{% endset %}
    {% set accessModifier %}{% if param.publicAccess %}public{% else %}internal{% endif %}{% endset %}
    {% set resourceType %}{{param.resourceTypeName|default:"File"}}{% endset %}
    import Foundation

    // swiftlint:disable superfluous_disable_command file_length line_length implicit_return

    // MARK: - Files

    {% macro groupBlock group %}
      {% for file in group.files %}
      {% call fileBlock file %}
      {% endfor %}
      {% for dir in group.directories %}
      {% call dirBlock dir "" %}
      {% endfor %}
    {% endmacro %}
    {% macro fileBlock file %}
      /// {%+ if file.path and param.preservePath %}{{file.path}}/{% endif %}{{file.name}}{% if file.ext %}.{{file.ext}}{% endif %}
      {% set identifier %}{{ file.name }}{% if useExt %}.{{ file.ext }}{% endif %}{% endset +%}
      {{accessModifier}} static let {{identifier|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}} = {{resourceType}}(name: "{{file.name}}", ext: {% if file.ext %}"{{file.ext}}"{% else %}nil{% endif %}, relativePath: "{{file.path if param.preservePath}}", mimeType: "{{file.mimeType}}")
    {% endmacro %}
    {% macro dirBlock directory parent %}
      {% set fullDir %}{{parent}}{{directory.name}}/{% endset %}
      /// {{ fullDir }}
      {{accessModifier}} enum {{directory.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% for file in directory.files %}
        {% filter indent:2 %}{% call fileBlock file %}{% endfilter %}
        {% endfor %}
        {% for dir in directory.directories %}
        {% filter indent:2 %}{% call dirBlock dir fullDir %}{% endfilter %}
        {% endfor %}
      }
    {% endmacro %}
    // swiftlint:disable explicit_type_interface identifier_name
    // swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
    {{accessModifier}} enum {{enumName}} {
      {% if groups.count > 1 or param.forceFileNameEnum %}
      {% for group in groups %}
      {{accessModifier}} enum {{group.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% filter indent:2 %}{% call groupBlock group %}{% endfilter %}
      }
      {% endfor %}
      {% else %}
      {% call groupBlock groups.first %}
      {% endif %}
    }
    // swiftlint:enable explicit_type_interface identifier_name
    // swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

    // MARK: - Implementation Details

    {{accessModifier}} struct {{resourceType}} {
      {{accessModifier}} let name: String
      {{accessModifier}} let ext: String?
      {{accessModifier}} let relativePath: String
      {{accessModifier}} let mimeType: String

      {{accessModifier}} var url: URL {
        return url(locale: nil)
      }

      {{accessModifier}} func url(locale: Locale?) -> URL {
        let bundle = {{param.bundle|default:"BundleToken.bundle"}}
        let url = bundle.url(
          forResource: name,
          withExtension: ext,
          subdirectory: relativePath,
          localization: locale?.identifier
        )
        guard let result = url else {
          let file = name + (ext.flatMap { "." + $0 } ?? "")
          fatalError("Could not locate file named" + file)
        }
        return result
      }

      {{accessModifier}} var path: String {
        return path(locale: nil)
      }

      {{accessModifier}} func path(locale: Locale?) -> String {
        return url(locale: locale).path
      }
    }
    {% if not param.bundle %}

    // swiftlint:disable convenience_type explicit_type_interface
    private final class BundleToken {
      static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: BundleToken.self)
        #endif
      }()
    }
    // swiftlint:enable convenience_type explicit_type_interface
    {% endif %}
    {% else %}
    // No files found
    {% endif %}
    // swiftlint:enable all
    // swiftformat:enable all

    """
}
