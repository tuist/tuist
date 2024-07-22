extension SynthesizedResourceInterfaceTemplates {
    static let plistsTemplate = """
    // swiftlint:disable all
    // swift-format-ignore-file
    // swiftformat:disable all
    // Generated using tuist — https://github.com/tuist/tuist

    {% if files %}
    {% set accessModifier %}{% if param.publicAccess %}public{% else %}internal{% endif %}{% endset %}
    import Foundation

    // swiftlint:disable superfluous_disable_command
    // swiftlint:disable file_length

    // MARK: - Plist Files
    {% macro fileBlock file %}
      {% call documentBlock file file.document %}
    {% endmacro %}
    {% macro documentBlock file document %}
      {% set rootType %}{% call typeBlock document.metadata %}{% endset %}
      {% if document.metadata.type == "Array" %}
      {{accessModifier}} static let items: {{rootType}} = {%+ call valueBlock document.data document.metadata +%}
      {% elif document.metadata.type == "Dictionary" %}
      {% for key,value in document.metadata.properties %}
      {{accessModifier}} {%+ call propertyBlock key value document.data %}
      {% endfor %}
      {% else %}
      {{accessModifier}} static let value: {{rootType}} = {%+ call valueBlock document.data document.metadata +%}
      {% endif %}
    {% endmacro %}
    {% macro typeBlock metadata %}
      {%- if metadata.type == "Array" -%}
        [{% call typeBlock metadata.element %}]
      {%- elif metadata.type == "Dictionary" -%}
        [String: Any]
      {%- else -%}
        {{metadata.type}}
      {%- endif -%}
    {% endmacro %}
    {% macro propertyBlock key metadata data %}
      {%- set propertyName %}{{key|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}}{% endset -%}
      {%- set propertyType %}{% call typeBlock metadata %}{% endset -%}
      static let {{propertyName}}: {{propertyType}} = {%+ call valueBlock data[key] metadata +%}
    {% endmacro %}
    {% macro valueBlock value metadata %}
      {%- if metadata.type == "String" -%}
        "{{ value }}"
      {%- elif metadata.type == "Date" -%}
        Date(timeIntervalSinceReferenceDate: {{ value.timeIntervalSinceReferenceDate }})
      {%- elif metadata.type == "Optional" -%}
        nil
      {%- elif metadata.type == "Array" and value -%}
        [{% for value in value -%}
          {%- call valueBlock value metadata.element.items[forloop.counter0]|default:metadata.element -%}
          {{ ", " if not forloop.last }}
        {%- endfor %}]
      {%- elif metadata.type == "Dictionary" -%}
        [{% for key,value in value -%}
          "{{key}}": {%+ call valueBlock value metadata.properties[key] -%}
          {{ ", " if not forloop.last }}
        {%- empty -%}
          :
        {%- endfor %}]
      {%- elif metadata.type == "Bool" -%}
        {%- if value %}true{% else %}false{% endif -%}
      {%- else -%}
        {{ value }}
      {%- endif -%}
    {% endmacro %}

    // swiftlint:disable identifier_name line_length number_separator type_body_length
    {% for file in files %}
    {{accessModifier}} enum {{file.name|swiftIdentifier:"pretty"|escapeReservedKeywords}}: Sendable {
      {% filter indent:2," ",true %}{% call fileBlock file %}{% endfilter %}
    }
    {% endfor %}
    // swiftlint:enable identifier_name line_length number_separator type_body_length
    {% else %}
    // No files found
    {% endif %}
    // swiftlint:enable all
    // swiftformat:enable all

    """
}
