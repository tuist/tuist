# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop checks for opportunities to use `assert_output`.
      #
      # @example
      #   # bad
      #   $stdout = StringIO.new
      #   puts object.method
      #   $stdout.rewind
      #   assert_match expected, $stdout.read
      #
      #   # good
      #   assert_output(expected) { puts object.method }
      #
      class AssertOutput < Base
        include MinitestExplorationHelpers

        MSG = 'Use `assert_output` instead of mutating %<name>s.'
        OUTPUT_GLOBAL_VARIABLES = %i[$stdout $stderr].freeze

        def on_gvasgn(node)
          test_case_node = find_test_case(node)
          return unless test_case_node

          gvar_name = node.children.first
          return unless OUTPUT_GLOBAL_VARIABLES.include?(gvar_name)

          assertions(test_case_node).each do |assertion|
            add_offense(assertion, message: format(MSG, name: gvar_name)) if references_gvar?(assertion, gvar_name)
          end
        end

        private

        def find_test_case(node)
          def_ancestor = node.each_ancestor(:def).first
          def_ancestor if test_case?(def_ancestor)
        end

        def references_gvar?(assertion, gvar_name)
          assertion.each_descendant(:gvar).any? { |d| d.children.first == gvar_name }
        end
      end
    end
  end
end
