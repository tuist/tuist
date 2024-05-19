extension SynthesizedResourceInterfaceTemplates {
    static let stringsCatalogTemplate = """
    // swiftlint:disable all
    // swift-format-ignore-file
    // swiftformat:disable all
    // Generated using tuist — https://github.com/tuist/tuist

    {% if files %}
    {% set accessModifier %}{% if param.publicAccess %}public{% else %}internal{% endif %}{% endset %}
    {% set bundleToken %}{{param.name}}Resources{% endset %}
    import Foundation

    // swiftlint:disable superfluous_disable_command file_length implicit_return

    // MARK: - Strings Catalog

    // swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
    // swiftlint:disable nesting type_body_length type_name
    {% set enumName %}{{param.name}}StringsCatalog{% endset %}
    {{accessModifier}} enum {{enumName}} {
      {% if files.count > 1 or param.forceFileNameEnum %}
      {% for file in files %}
      {{accessModifier}} enum {{file.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {# {% filter indent:2 %}{% call recursiveBlock table.name table.levels %}{% endfilter %} #}
      }
      {% endfor %}
      {% else %}
      {# {% call recursiveBlock files.first.name files.first.levels %} #}
      {% endif %}
    }

    // swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
    // swiftlint:enable nesting type_body_length type_name


    // MARK: - Implementation Details

    {% set enumName %}{{param.name}}StringsCatalog{% endset %}
    extension {{enumName}} {
      private static func tr(_ table: String, _ key: StaticString, defaultValue: String.LocalizationValue, comment: StaticString?) -> String {
        return String(
          localized: key,
          defaultValue: defaultValue,
          table: table,
          bundle: {{bundleToken}}.bundle,
          locale: .current,
          comment: comment
        )
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
