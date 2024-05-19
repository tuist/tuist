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

    {% macro documentBlock file document %}
      {% if document.metadata.type == "Dictionary" %}
        {% for key,value in document.metadata.properties %}
      {% call propertyBlock key value document.data %}
    {% endfor %}
    {% endif %}
    {% endmacro %}

    {# process the root dictionary #}
    {% macro propertyBlock key metadata data %}
    {% set propertyName %}{{key|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}}{% endset %}
    {% if propertyName == "strings" %}
          {% set sourceLanguage %}{{ data.sourceLanguage }}{% endset %}
          {% for propertyKey in data[key] %}
          {% set propertyComment %}{{ data[key][propertyKey].comment }}{% endset %}
          {% set propertyValue %}{{data[key][propertyKey].localizations[sourceLanguage].stringUnit.value}}{% endset %}
          {% set propertyPlural %}{{data[key][propertyKey].localizations[sourceLanguage].variations.plural}}{% endset %}
          {% set propertyDevice %}{{data[key][propertyKey].localizations[sourceLanguage].variations.device}}{% endset %}
          {# Strings keys #}
          // {{ propertyKey }}
        {% endfor %}
      {% else %}
      {% endif %}
    {% endmacro %}

    // swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
    // swiftlint:disable nesting type_body_length type_name
    {% set enumName %}{{param.name}}StringsCatalog{% endset %}
    {{accessModifier}} enum {{enumName}} {
      {% if files.count > 1 or param.forceFileNameEnum %}
      {% for file in files %}
      {{accessModifier}} enum {{file.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% call documentBlock file file.document %}
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
