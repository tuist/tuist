// swiftlint:disable line_length
extension SynthesizedResourceInterfaceTemplates {
    static let assetsTemplate = """
    // swiftlint:disable all
    // swift-format-ignore-file
    // swiftformat:disable all
    // Generated using tuist — https://github.com/tuist/tuist

    {% if catalogs %}
    {% set enumName %}{{param.name}}Asset{% endset %}
    {% set arResourceGroupType %}{{param.name}}ARResourceGroup{% endset %}
    {% set colorType %}{{param.name}}Colors{% endset %}
    {% set dataType %}{{param.name}}Data{% endset %}
    {% set imageType %}{{param.name}}Images{% endset %}
    {% set forceNamespaces %}{{param.forceProvidesNamespaces|default:"false"}}{% endset %}
    {% set bundleToken %}{{param.name}}Resources{% endset %}
    {% set accessModifier %}{% if param.publicAccess %}public{% else %}internal{% endif %}{% endset %}
    #if os(macOS)
      import AppKit
    #elseif os(iOS)
    {% if resourceCount.arresourcegroup > 0 %}
      import ARKit
    {% endif %}
      import UIKit
    #elseif os(tvOS) || os(watchOS)
      import UIKit
    #endif

    // swiftlint:disable superfluous_disable_command file_length implicit_return

    // MARK: - Asset Catalogs

    {% macro enumBlock assets %}
      {% call casesBlock assets %}
      {% if param.allValues %}

      // swiftlint:disable trailing_comma
      {% if resourceCount.arresourcegroup > 0 %}
      {{accessModifier}} static let allResourceGroups: [{{arResourceGroupType}}] = [
        {% filter indent:2 %}{% call allValuesBlock assets "arresourcegroup" "" %}{% endfilter %}
      ]
      {% endif %}
      {% if resourceCount.color > 0 %}
      {{accessModifier}} static let allColors: [{{colorType}}] = [
        {% filter indent:2 %}{% call allValuesBlock assets "color" "" %}{% endfilter %}
      ]
      {% endif %}
      {% if resourceCount.data > 0 %}
      {{accessModifier}} static let allDataAssets: [{{dataType}}] = [
        {% filter indent:2 %}{% call allValuesBlock assets "data" "" %}{% endfilter %}
      ]
      {% endif %}
      {% if resourceCount.image > 0 %}
      {{accessModifier}} static let allImages: [{{imageType}}] = [
        {% filter indent:2 %}{% call allValuesBlock assets "image" "" %}{% endfilter %}
      ]
      {% endif %}
      // swiftlint:enable trailing_comma
      {% endif %}
    {% endmacro %}
    {% macro casesBlock assets %}
      {% for asset in assets %}
      {% if asset.type == "arresourcegroup" %}
      {{accessModifier}} static let {{asset.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}} = {{arResourceGroupType}}(name: "{{asset.value}}")
      {% elif asset.type == "color" %}
      {{accessModifier}} static let {{asset.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}} = {{colorType}}(name: "{{asset.value}}")
      {% elif asset.type == "data" %}
      {{accessModifier}} static let {{asset.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}} = {{dataType}}(name: "{{asset.value}}")
      {% elif asset.type == "image" %}
      {{accessModifier}} static let {{asset.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}} = {{imageType}}(name: "{{asset.value}}")
      {% elif asset.items and ( forceNamespaces == "true" or asset.isNamespaced == "true" ) %}
      {{accessModifier}} enum {{asset.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% filter indent:2 %}{% call casesBlock asset.items %}{% endfilter %}
      }
      {% elif asset.items %}
      {% call casesBlock asset.items %}
      {% endif %}
      {% endfor %}
    {% endmacro %}
    {% macro allValuesBlock assets filter prefix %}
      {% for asset in assets %}
      {% if asset.type == filter %}
      {{prefix}}{{asset.name|swiftIdentifier:"pretty"|lowerFirstWord|escapeReservedKeywords}},
      {% elif asset.items and ( forceNamespaces == "true" or asset.isNamespaced == "true" ) %}
      {% set prefix2 %}{{prefix}}{{asset.name|swiftIdentifier:"pretty"|escapeReservedKeywords}}.{% endset %}
      {% call allValuesBlock asset.items filter prefix2 %}
      {% elif asset.items %}
      {% call allValuesBlock asset.items filter prefix %}
      {% endif %}
      {% endfor %}
    {% endmacro %}
    // swiftlint:disable identifier_name line_length nesting type_body_length type_name
    {{accessModifier}} enum {{enumName}} {
      {% if catalogs.count > 1 or param.forceFileNameEnum %}
      {% for catalog in catalogs %}
      {{accessModifier}} enum {{catalog.name|swiftIdentifier:"pretty"|escapeReservedKeywords}} {
        {% filter indent:2 %}{% call enumBlock catalog.assets %}{% endfilter %}
      }
      {% endfor %}
      {% else %}
      {% call enumBlock catalogs.first.assets %}
      {% endif %}
    }
    // swiftlint:enable identifier_name line_length nesting type_body_length type_name

    // MARK: - Implementation Details

    {% if resourceCount.arresourcegroup > 0 %}
    {{accessModifier}} struct {{arResourceGroupType}} {
      {{accessModifier}} fileprivate(set) var name: String

      #if os(iOS)
      @available(iOS 11.3, *)
      {{accessModifier}} var referenceImages: Set<ARReferenceImage> {
        return ARReferenceImage.referenceImages(in: self)
      }

      @available(iOS 12.0, *)
      {{accessModifier}} var referenceObjects: Set<ARReferenceObject> {
        return ARReferenceObject.referenceObjects(in: self)
      }
      #endif
    }

    #if os(iOS)
    @available(iOS 11.3, *)
    {{accessModifier}} extension ARReferenceImage {
      static func referenceImages(in asset: {{arResourceGroupType}}) -> Set<ARReferenceImage> {
        let bundle = .bundle
        return referenceImages(inGroupNamed: asset.name, bundle: bundle) ?? Set()
      }
    }

    @available(iOS 12.0, *)
    {{accessModifier}} extension ARReferenceObject {
      static func referenceObjects(in asset: {{arResourceGroupType}}) -> Set<ARReferenceObject> {
        let bundle = {{bundleToken}}.bundle
        return referenceObjects(inGroupNamed: asset.name, bundle: bundle) ?? Set()
      }
    }
    #endif

    {% endif %}
    {% if resourceCount.color > 0 %}
    {{accessModifier}} final class {{colorType}} {
      {{accessModifier}} fileprivate(set) var name: String

      #if os(macOS)
      {{accessModifier}} typealias Color = NSColor
      #elseif os(iOS) || os(tvOS) || os(watchOS)
      {{accessModifier}} typealias Color = UIColor
      #endif

      @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *)
      {{accessModifier}} private(set) lazy var color: Color = {
        guard let color = Color(asset: self) else {
          fatalError("Unable to load color asset named \\(name).")
        }
        return color
      }()

      fileprivate init(name: String) {
        self.name = name
      }
    }

    {{accessModifier}} extension {{colorType}}.Color {
      @available(iOS 11.0, tvOS 11.0, watchOS 4.0, macOS 10.13, *)
      convenience init?(asset: {{colorType}}) {
        let bundle = {{bundleToken}}.bundle
        #if os(iOS) || os(tvOS)
        self.init(named: asset.name, in: bundle, compatibleWith: nil)
        #elseif os(macOS)
        self.init(named: NSColor.Name(asset.name), bundle: bundle)
        #elseif os(watchOS)
        self.init(named: asset.name)
        #endif
      }
    }

    {% endif %}
    {% if resourceCount.data > 0 %}
    {{accessModifier}} struct {{dataType}} {
      {{accessModifier}} fileprivate(set) var name: String

      #if os(iOS) || os(tvOS) || os(macOS)
      @available(iOS 9.0, macOS 10.11, *)
      {{accessModifier}} var data: NSDataAsset {
        guard let data = NSDataAsset(asset: self) else {
          fatalError("Unable to load data asset named \\(name).")
        }
        return data
      }
      #endif
    }

    #if os(iOS) || os(tvOS) || os(macOS)
    @available(iOS 9.0, macOS 10.11, *)
    {{accessModifier}} extension NSDataAsset {
      convenience init?(asset: {{dataType}}) {
        let bundle = {{bundleToken}}.bundle
        #if os(iOS) || os(tvOS)
        self.init(name: asset.name, bundle: bundle)
        #elseif os(macOS)
        self.init(name: NSDataAsset.Name(asset.name), bundle: bundle)
        #endif
      }
    }
    #endif

    {% endif %}
    {% if resourceCount.image > 0 %}
    {{accessModifier}} struct {{imageType}} {
      {{accessModifier}} fileprivate(set) var name: String

      #if os(macOS)
      {{accessModifier}} typealias Image = NSImage
      #elseif os(iOS) || os(tvOS) || os(watchOS)
      {{accessModifier}} typealias Image = UIImage
      #endif

      {{accessModifier}} var image: Image {
        let bundle = {{bundleToken}}.bundle
        #if os(iOS) || os(tvOS)
        let image = Image(named: name, in: bundle, compatibleWith: nil)
        #elseif os(macOS)
        let image = bundle.image(forResource: NSImage.Name(name))
        #elseif os(watchOS)
        let image = Image(named: name)
        #endif
        guard let result = image else {
          fatalError("Unable to load image asset named \\(name).")
        }
        return result
      }
    }

    {{accessModifier}} extension {{imageType}}.Image {
      @available(macOS, deprecated,
        message: "This initializer is unsafe on macOS, please use the {{imageType}}.image property")
      convenience init?(asset: {{imageType}}) {
        #if os(iOS) || os(tvOS)
        let bundle = {{bundleToken}}.bundle
        self.init(named: asset.name, in: bundle, compatibleWith: nil)
        #elseif os(macOS)
        self.init(named: NSImage.Name(asset.name))
        #elseif os(watchOS)
        self.init(named: asset.name)
        #endif
      }
    }

    {% endif %}
    {% else %}
    // No assets found
    {% endif %}
    // swiftlint:enable all
    // swiftformat:enable all

    """
}
