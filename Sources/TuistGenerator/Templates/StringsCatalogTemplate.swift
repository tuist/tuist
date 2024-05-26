extension SynthesizedResourceInterfaceTemplates {
    static let stringsCatalogTemplate = """
    // swiftlint:disable all
    // swift-format-ignore-file
    // swiftformat:disable all
    // Generated using tuist — https://github.com/tuist/tuist

    {% if tables.count > 0 %}
    {% set accessModifier %}{% if param.publicAccess %}public{% else %}internal{% endif %}{% endset %}
    {% set bundleToken %}{{param.name}}Resources{% endset %}
    import Foundation

    // swiftlint:disable superfluous_disable_command file_length implicit_return

    // MARK: - Strings

    {% macro parametersBlock types %}{% filter removeNewlines:"leading" %}
      {% for type in types %}
        {% if type == "String" %}
        _ p{{forloop.counter}}: Any
        {% else %}
        _ p{{forloop.counter}}: {{type}}
        {% endif %}
        {{ ", " if not forloop.last }}
      {% endfor %}
    {% endfilter %}{% endmacro %}
    {% macro argumentsBlock types %}{% filter removeNewlines:"leading" %}
      {% for type in types %}
        {% if type == "String" %}
        String(describing: p{{forloop.counter}})
        {% elif type == "UnsafeRawPointer" %}
        Int(bitPattern: p{{forloop.counter}})
        {% else %}
        p{{forloop.counter}}
        {% endif %}
        {{ ", " if not forloop.last }}
      {% endfor %}
    {% endfilter %}{% endmacro %}
    {% macro recursiveBlock table item %}
      {% for string in item.strings %}
      {% if not param.noComments %}
      /// {{string.translation}}
      {% endif %}
      {% if string.types %}
      {{accessModifier}} static func {{string.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}}({% call parametersBlock string.types %}) -> String {
        return {{enumName}}.string("{{table}}", "{{string.key}}", "{{string.comment}}", {% call argumentsBlock string.types %})
      }
      {% elif param.lookupFunction %}
      {# custom localization function is mostly used for in-app lang selection, so we want the loc to be recomputed at each call for those (hence the computed var) #}
      {{accessModifier}} static var {{string.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}}: String { return {{enumName}}.string("{{table}}", "{{string.key}}", "{{string.comment}}")
      {% else %}
      {{accessModifier}} static let {{string.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}} = {{enumName}}.string("{{table}}", "{{string.key}}", "{{string.comment}}")
      {% endif %}
      {% endfor %}
      {% for child in item.children %}

      {{accessModifier}} enum {{child.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% filter indent:2 %}{% call recursiveBlock table child %}{% endfilter %}
      }
      {% endfor %}
    {% endmacro %}
    // swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
    // swiftlint:disable nesting type_body_length type_name
    {% set enumName %}{{param.name}}StringsCatalog{% endset %}
    {{accessModifier}} enum {{enumName}} {
      {% if tables.count > 1 or param.forceFileNameEnum %}
      {% for table in tables %}
      {{accessModifier}} enum {{table.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% filter indent:2 %}{% call recursiveBlock table.name table.levels %}{% endfilter %}
      }
      {% endfor %}
      {% else %}
      {% call recursiveBlock tables.first.name tables.first.levels %}
      {% endif %}
    }
    // swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
    // swiftlint:enable nesting type_body_length type_name

    // MARK: - Implementation Details

    {% set enumName %}{{param.name}}StringsCatalog{% endset %}
    extension {{enumName}} {
      private static func string(_ table: String, _ key: StaticString, _ comment: StaticString?, _ args: CVarArg...) -> String {
        return String(
          localized: key,
          defaultValue: defaultValue(key, args),
          table: table,
          bundle: {{bundleToken}}.bundle,
          locale: .current,
          comment: comment
        )
      }

      private static func resource(_ table: String, _ key: StaticString, _ comment: StaticString?, _ args: CVarArg...) -> LocalizedStringResource {
        return LocalizedStringResource(
          key,
          defaultValue: defaultValue(key, args),
          table: table,
          locale: .current,
          bundle: .forClass({{bundleToken}}.self),
          comment: comment
        )
      }
      private static func defaultValue(_ key: StaticString,
                                       _ args: CVarArg...) -> String.LocalizationValue {
        var stringInterpolation = String.LocalizationValue.StringInterpolation(literalCapacity: 0, interpolationCount: args.count)
        args.forEach { stringInterpolation.appendInterpolation(arg: $0) }
        return .init(stringInterpolation: stringInterpolation)
      }
    }
    
    private extension String.LocalizationValue.StringInterpolation {
        mutating func appendInterpolation(arg: CVarArg) {
            switch arg {
            case let arg as String: appendInterpolation(arg)
            case let arg as Int: appendInterpolation(arg)
            case let arg as UInt: appendInterpolation(arg)
            case let arg as Double: appendInterpolation(arg)
            case let arg as Float: appendInterpolation(arg)
            default: return
            }
        }
    }
    {% if not param.lookupFunction %}

    // swiftlint:disable convenience_type
    {% endif %}
    {% else %}
    // No string found
    {% endif %}
    // swiftlint:enable all
    // swiftformat:enable all


    """
}
