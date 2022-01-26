# frozen_string_literal: true

require "rubocop/packaging/lib_helper_module"

module RuboCop # :nodoc:
  module Cop # :nodoc:
    module Packaging # :nodoc:
      # This cop flags the `require` calls, from anywhere mapping to
      # the "lib" directory, except originating from lib/.
      #
      # @example
      #
      #   # bad
      #   require "../lib/foo/bar"
      #
      #   # good
      #   require "foo/bar"
      #
      #   # bad
      #   require File.expand_path("../../lib/foo", __FILE__)
      #
      #   # good
      #   require "foo"
      #
      #   # bad
      #   require File.expand_path("../../../lib/foo/bar/baz/qux", __dir__)
      #
      #   # good
      #   require "foo/bar/baz/qux"
      #
      #   # bad
      #   require File.dirname(__FILE__) + "/../../lib/baz/qux"
      #
      #   # good
      #   require "baz/qux"
      #
      class RequireHardcodingLib < Base
        include RuboCop::Packaging::LibHelperModule
        extend AutoCorrector

        # This is the message that will be displayed when RuboCop::Packaging
        # finds an offense of using `require` with relative path to lib.
        MSG = "Avoid using `require` with relative path to `lib/`. " \
              "Use `require` with absolute path instead."

        def_node_matcher :require?, <<~PATTERN
          {(send nil? :require (str #falls_in_lib?))
           (send nil? :require (send (const nil? :File) :expand_path (str #falls_in_lib?) (send nil? :__dir__)))
           (send nil? :require (send (const nil? :File) :expand_path (str #falls_in_lib_using_file?) (str _)))
           (send nil? :require (send (send (const nil? :File) :dirname {(str _) (send nil? _)}) :+ (str #falls_in_lib_with_file_dirname_plus_str?)))
           (send nil? :require (dstr (begin (send (const nil? :File) :dirname {(str _) (send nil? _)})) (str #falls_in_lib_with_file_dirname_plus_str?)))}
        PATTERN

        # Extended from the Base class.
        # More about the `#on_new_investigation` method can be found here:
        # https://github.com/rubocop-hq/rubocop/blob/343f62e4555be0470326f47af219689e21c61a37/lib/rubocop/cop/base.rb
        #
        # Processing of the AST happens here.
        def on_new_investigation
          @file_path = processed_source.file_path
          @file_directory = File.dirname(@file_path)
        end

        # Extended from AST::Traversal.
        # More about the `#on_send` method can be found here:
        # https://github.com/rubocop-hq/rubocop-ast/blob/08d0f49a47af1e9a30a6d8f67533ba793c843d67/lib/rubocop/ast/traversal.rb#L112
        def on_send(node)
          return unless require?(node)

          add_offense(node) do |corrector|
            corrector.replace(node, good_require_call)
          end
        end

        # Called from on_send, this method helps to replace
        # the "bad" require call with the "good" one.
        def good_require_call
          good_call = @str.sub(%r{^.*/lib/}, "")
          %(require "#{good_call}")
        end

        # This method is called from inside `#def_node_matcher`.
        # It flags an offense if the `require` call is made from
        # anywhere except the "lib" directory.
        def falls_in_lib?(str)
          @str = str
          target_falls_in_lib?(str) && inspected_file_is_not_in_lib_or_gemspec?
        end

        # This method is called from inside `#def_node_matcher`.
        # It flags an offense if the `require` call (using the __FILE__
        # arguement) is made from anywhere except the "lib" directory.
        def falls_in_lib_using_file?(str)
          @str = str
          target_falls_in_lib_using_file?(str) && inspected_file_is_not_in_lib_or_gemspec?
        end

        # This method preprends a "." to the string that starts with "/".
        # And then determines if that call is made to "lib/".
        def falls_in_lib_with_file_dirname_plus_str?(str)
          @str = str
          str.prepend(".")
          target_falls_in_lib?(str) && inspected_file_is_not_in_lib_or_gemspec?
        end
      end
    end
  end
end
