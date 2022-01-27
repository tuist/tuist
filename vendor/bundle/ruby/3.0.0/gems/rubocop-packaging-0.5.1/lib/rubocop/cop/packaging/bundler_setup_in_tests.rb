# frozen_string_literal: true

require "rubocop/packaging/lib_helper_module"

module RuboCop # :nodoc:
  module Cop # :nodoc:
    module Packaging # :nodoc:
      # This cop flags the `require "bundler/setup"` calls if they're
      # made from inside the tests directory.
      #
      # @example
      #
      #   # bad
      #   require "foo"
      #   require "bundler/setup"
      #
      #   # good
      #   require "foo"
      #
      class BundlerSetupInTests < Base
        include RuboCop::Packaging::LibHelperModule
        include RangeHelp
        extend AutoCorrector

        # This is the message that will be displayed when RuboCop::Packaging finds
        # an offense of using `require "bundler/setup"` in the tests directory.
        MSG = "Using `bundler/setup` in tests is redundant. Consider removing it."

        def_node_matcher :bundler_setup?, <<~PATTERN
          (send nil? :require
            (str #bundler_setup_in_test_dir?))
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
          return unless bundler_setup?(node)

          add_offense(node) do |corrector|
            autocorrect(corrector, node)
          end
        end

        # Called from on_send, this method helps to autocorrect
        # the offenses flagged by this cop.
        def autocorrect(corrector, node)
          range = range_by_whole_lines(node.source_range, include_final_newline: true)

          corrector.remove(range)
        end

        # This method is called from inside `#def_node_matcher`.
        # It flags an offense if the `require "bundler/setup"`
        # call is made from the tests directory.
        def bundler_setup_in_test_dir?(str)
          str.eql?("bundler/setup") && falls_in_test_dir?
        end

        # This method determines if the call is made *from* the tests directory.
        def falls_in_test_dir?
          %w[spec specs test tests].any? { |dir| File.expand_path(@file_directory).start_with?("#{root_dir}/#{dir}") }
        end
      end
    end
  end
end
