# frozen_string_literal: true
require "cgi"
require "crass"

module Loofah
  module HTML5 # :nodoc:
    module Scrub
      CONTROL_CHARACTERS = /[`\u0000-\u0020\u007f\u0080-\u0101]/
      CSS_KEYWORDISH = /\A(#[0-9a-fA-F]+|rgb\(\d+%?,\d*%?,?\d*%?\)?|-?\d{0,3}\.?\d{0,10}(ch|cm|r?em|ex|in|lh|mm|pc|pt|px|Q|vmax|vmin|vw|vh|%|,|\))?)\z/
      CRASS_SEMICOLON = { node: :semicolon, raw: ";" }
      CSS_IMPORTANT = '!important'
      CSS_PROPERTY_STRING_WITHOUT_EMBEDDED_QUOTES = /\A(["'])?[^"']+\1\z/
      DATA_ATTRIBUTE_NAME = /\Adata-[\w-]+\z/

      class << self
        def allowed_element?(element_name)
          ::Loofah::HTML5::SafeList::ALLOWED_ELEMENTS_WITH_LIBXML2.include?(element_name)
        end

        #  alternative implementation of the html5lib attribute scrubbing algorithm
        def scrub_attributes(node)
          node.attribute_nodes.each do |attr_node|
            attr_name = if attr_node.namespace
              "#{attr_node.namespace.prefix}:#{attr_node.node_name}"
            else
              attr_node.node_name
            end

            if attr_name =~ DATA_ATTRIBUTE_NAME
              next
            end

            unless SafeList::ALLOWED_ATTRIBUTES.include?(attr_name)
              attr_node.remove
              next
            end

            if SafeList::ATTR_VAL_IS_URI.include?(attr_name)
              # this block lifted nearly verbatim from HTML5 sanitization
              val_unescaped = CGI.unescapeHTML(attr_node.value).gsub(CONTROL_CHARACTERS, "").downcase
              if val_unescaped =~ /^[a-z0-9][-+.a-z0-9]*:/ && !SafeList::ALLOWED_PROTOCOLS.include?(val_unescaped.split(SafeList::PROTOCOL_SEPARATOR)[0])
                attr_node.remove
                next
              elsif val_unescaped.split(SafeList::PROTOCOL_SEPARATOR)[0] == "data"
                # permit only allowed data mediatypes
                mediatype = val_unescaped.split(SafeList::PROTOCOL_SEPARATOR)[1]
                mediatype, _ = mediatype.split(";")[0..1] if mediatype
                if mediatype && !SafeList::ALLOWED_URI_DATA_MEDIATYPES.include?(mediatype)
                  attr_node.remove
                  next
                end
              end
            end
            if SafeList::SVG_ATTR_VAL_ALLOWS_REF.include?(attr_name)
              attr_node.value = attr_node.value.gsub(/url\s*\(\s*[^#\s][^)]+?\)/m, " ") if attr_node.value
            end
            if SafeList::SVG_ALLOW_LOCAL_HREF.include?(node.name) && attr_name == "xlink:href" && attr_node.value =~ /^\s*[^#\s].*/m
              attr_node.remove
              next
            end
          end

          scrub_css_attribute(node)

          node.attribute_nodes.each do |attr_node|
            if attr_node.value !~ /[^[:space:]]/ && attr_node.name !~ DATA_ATTRIBUTE_NAME
              node.remove_attribute(attr_node.name)
            end
          end

          force_correct_attribute_escaping!(node)
        end

        def scrub_css_attribute(node)
          style = node.attributes["style"]
          style.value = scrub_css(style.value) if style
        end

        def scrub_css(style)
          style_tree = Crass.parse_properties(style)
          sanitized_tree = []

          style_tree.each do |node|
            next unless node[:node] == :property
            next if node[:children].any? do |child|
              [:url, :bad_url].include?(child[:node])
            end

            name = node[:name].downcase
            next unless SafeList::ALLOWED_CSS_PROPERTIES.include?(name) ||
                SafeList::ALLOWED_SVG_PROPERTIES.include?(name) ||
                SafeList::SHORTHAND_CSS_PROPERTIES.include?(name.split("-").first)

            value = node[:children].map do |child|
              case child[:node]
              when :whitespace
                nil
              when :string
                if child[:raw] =~ CSS_PROPERTY_STRING_WITHOUT_EMBEDDED_QUOTES
                  Crass::Parser.stringify(child)
                else
                  nil
                end
              when :function
                if SafeList::ALLOWED_CSS_FUNCTIONS.include?(child[:name].downcase)
                  Crass::Parser.stringify(child)
                end
              when :ident
                keyword = child[:value]
                if !SafeList::SHORTHAND_CSS_PROPERTIES.include?(name.split("-").first) ||
                   SafeList::ALLOWED_CSS_KEYWORDS.include?(keyword) ||
                   (keyword =~ CSS_KEYWORDISH)
                  keyword
                end
              else
                child[:raw]
              end
            end.compact

            next if value.empty?
            value << CSS_IMPORTANT if node[:important]
            propstring = format("%s:%s", name, value.join(" "))
            sanitized_node = Crass.parse_properties(propstring).first
            sanitized_tree << sanitized_node << CRASS_SEMICOLON
          end

          Crass::Parser.stringify(sanitized_tree)
        end

        #
        #  libxml2 >= 2.9.2 fails to escape comments within some attributes.
        #
        #  see comments about CVE-2018-8048 within the tests for more information
        #
        def force_correct_attribute_escaping!(node)
          return unless Nokogiri::VersionInfo.instance.libxml2?

          node.attribute_nodes.each do |attr_node|
            next unless LibxmlWorkarounds::BROKEN_ESCAPING_ATTRIBUTES.include?(attr_node.name)

            tag_name = LibxmlWorkarounds::BROKEN_ESCAPING_ATTRIBUTES_QUALIFYING_TAG[attr_node.name]
            next unless tag_name.nil? || tag_name == node.name

            #
            #  this block is just like CGI.escape in Ruby 2.4, but
            #  only encodes space and double-quote, to mimic
            #  pre-2.9.2 behavior
            #
            encoding = attr_node.value.encoding
            attr_node.value = attr_node.value.gsub(/[ "]/) do |m|
              "%" + m.unpack("H2" * m.bytesize).join("%").upcase
            end.force_encoding(encoding)
          end
        end
      end
    end
  end
end
