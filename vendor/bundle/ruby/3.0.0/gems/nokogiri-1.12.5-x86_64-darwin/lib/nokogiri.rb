# -*- coding: utf-8 -*-
# frozen_string_literal: true
# Modify the PATH on windows so that the external DLLs will get loaded.

require "rbconfig"

if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
  require_relative "nokogiri/jruby/dependencies"
end

require_relative "nokogiri/extension"

# Nokogiri parses and searches XML/HTML very quickly, and also has
# correctly implemented CSS3 selector support as well as XPath 1.0
# support.
#
# Parsing a document returns either a Nokogiri::XML::Document, or a
# Nokogiri::HTML4::Document depending on the kind of document you parse.
#
# Here is an example:
#
#   require 'nokogiri'
#   require 'open-uri'
#
#   # Get a Nokogiri::HTML4::Document for the page we’re interested in...
#
#   doc = Nokogiri::HTML4(URI.open('http://www.google.com/search?q=tenderlove'))
#
#   # Do funky things with it using Nokogiri::XML::Node methods...
#
#   ####
#   # Search for nodes by css
#   doc.css('h3.r a.l').each do |link|
#     puts link.content
#   end
#
# See Nokogiri::XML::Searchable#css for more information about CSS searching.
# See Nokogiri::XML::Searchable#xpath for more information about XPath searching.
module Nokogiri
  class << self
    ###
    # Parse an HTML or XML document.  +string+ contains the document.
    def parse(string, url = nil, encoding = nil, options = nil)
      if string.respond_to?(:read) ||
          /^\s*<(?:!DOCTYPE\s+)?html[\s>]/i === string[0, 512]
        # Expect an HTML indicator to appear within the first 512
        # characters of a document. (<?xml ?> + <?xml-stylesheet ?>
        # shouldn't be that long)
        Nokogiri.HTML4(string, url, encoding,
          options || XML::ParseOptions::DEFAULT_HTML)
      else
        Nokogiri.XML(string, url, encoding,
          options || XML::ParseOptions::DEFAULT_XML)
      end.tap do |doc|
        yield doc if block_given?
      end
    end

    ###
    # Create a new Nokogiri::XML::DocumentFragment
    def make(input = nil, opts = {}, &blk)
      if input
        Nokogiri::HTML4.fragment(input).children.first
      else
        Nokogiri(&blk)
      end
    end

    ###
    # Parse a document and add the Slop decorator.  The Slop decorator
    # implements method_missing such that methods may be used instead of CSS
    # or XPath.  For example:
    #
    #   doc = Nokogiri::Slop(<<-eohtml)
    #     <html>
    #       <body>
    #         <p>first</p>
    #         <p>second</p>
    #       </body>
    #     </html>
    #   eohtml
    #   assert_equal('second', doc.html.body.p[1].text)
    #
    def Slop(*args, &block)
      Nokogiri(*args, &block).slop!
    end

    def install_default_aliases
      # Make sure to support some popular encoding aliases not known by
      # all iconv implementations.
      {
        "Windows-31J" => "CP932",	# Windows-31J is the IANA registered name of CP932.
      }.each do |alias_name, name|
        EncodingHandler.alias(name, alias_name) if EncodingHandler[alias_name].nil?
      end
    end
  end

  Nokogiri.install_default_aliases
end

###
# Parse a document contained in +args+.  Nokogiri will try to guess what type of document you are
# attempting to parse.  For more information, see Nokogiri.parse
#
# To specify the type of document, use {Nokogiri.XML}, {Nokogiri.HTML4}, or {Nokogiri.HTML5}.
def Nokogiri(*args, &block)
  if block_given?
    Nokogiri::HTML4::Builder.new(&block).doc.root
  else
    Nokogiri.parse(*args)
  end
end

require_relative "nokogiri/version"
require_relative "nokogiri/syntax_error"
require_relative "nokogiri/xml"
require_relative "nokogiri/xslt"
require_relative "nokogiri/html4"
require_relative "nokogiri/html"
require_relative "nokogiri/decorators/slop"
require_relative "nokogiri/css"
require_relative "nokogiri/html4/builder"

require_relative "nokogiri/html5" if Nokogiri.uses_gumbo?
