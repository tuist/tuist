# frozen_string_literal: true

require 'set'

module RuboCop
  module Cop
    # Helper methods for different explorations against test files and test cases.
    module MinitestExplorationHelpers
      extend NodePattern::Macros

      ASSERTION_PREFIXES = %w[assert refute].freeze

      ASSERTION_METHODS = %i[
        assert assert_empty assert_equal assert_in_delta assert_in_epsilon assert_includes assert_instance_of
        assert_kind_of assert_match assert_nil assert_operator assert_output assert_path_exists assert_predicate
        assert_raises assert_respond_to assert_same assert_send assert_silent assert_throws
        refute refute_empty refute_equal refute_in_delta refute_in_epsilon refute_includes refute_instance_of
        refute_kind_of refute_match refute_nil refute_operator refute_path_exists refute_predicate
        refute_respond_to refute_same
      ].freeze

      FLUNK = 'flunk'

      LIFECYCLE_HOOK_METHODS = %i[
        before_setup
        setup
        after_setup
        before_teardown
        teardown
        after_teardown
      ].to_set.freeze

      private

      def test_class?(class_node)
        class_node.parent_class && class_node.identifier.source.end_with?('Test')
      end

      def test_case?(node)
        return false unless node&.def_type? && test_case_name?(node.method_name)

        class_ancestor = node.each_ancestor(:class).first
        test_class?(class_ancestor)
      end

      def test_cases(class_node)
        class_def_nodes(class_node).select { |def_node| test_case_name?(def_node.method_name) }
      end

      def lifecycle_hooks(class_node)
        class_def_nodes(class_node)
          .select { |def_node| lifecycle_hook_method?(def_node) }
      end

      def class_def_nodes(class_node)
        class_def = class_node.body
        return [] unless class_def

        if class_def.def_type?
          [class_def]
        else
          class_def.each_child_node(:def).to_a
        end
      end

      def test_case_name?(name)
        name.to_s.start_with?('test_')
      end

      def assertions(def_node)
        method_def = def_node.body
        return [] unless method_def

        send_nodes =
          if method_def.send_type?
            [method_def]
          else
            method_def.each_child_node(:send)
          end

        send_nodes.select { |send_node| assertion?(send_node) }
      end

      def assertion?(node)
        node.send_type? &&
          ASSERTION_PREFIXES.any? do |prefix|
            method_name = node.method_name.to_s
            method_name == FLUNK || method_name.start_with?(prefix)
          end
      end

      def assertion_method?(method_name)
        method_name == FLUNK || ASSERTION_METHODS.include?(method_name)
      end

      def lifecycle_hook_method?(node)
        node.def_type? && LIFECYCLE_HOOK_METHODS.include?(node.method_name)
      end
    end
  end
end
