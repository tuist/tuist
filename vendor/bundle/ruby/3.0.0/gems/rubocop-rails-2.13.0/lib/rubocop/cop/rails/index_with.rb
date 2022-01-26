# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop looks for uses of `each_with_object({}) { ... }`,
      # `map { ... }.to_h`, and `Hash[map { ... }]` that are transforming
      # an enumerable into a hash where the keys are the original elements.
      # Rails provides the `index_with` method for this purpose.
      #
      # @example
      #   # bad
      #   [1, 2, 3].each_with_object({}) { |el, h| h[el] = foo(el) }
      #   [1, 2, 3].to_h { |el| [el, foo(el)] }
      #   [1, 2, 3].map { |el| [el, foo(el)] }.to_h
      #   Hash[[1, 2, 3].collect { |el| [el, foo(el)] }]
      #
      #   # good
      #   [1, 2, 3].index_with { |el| foo(el) }
      class IndexWith < Base
        extend AutoCorrector
        extend TargetRailsVersion
        include IndexMethod

        minimum_target_rails_version 6.0

        def_node_matcher :on_bad_each_with_object, <<~PATTERN
          (block
            ({send csend} _ :each_with_object (hash))
            (args (arg $_el) (arg _memo))
            ({send csend} (lvar _memo) :[]= (lvar _el) $!`_memo))
        PATTERN

        def_node_matcher :on_bad_to_h, <<~PATTERN
          (block
            ({send csend} _ :to_h)
            (args (arg $_el))
            (array (lvar _el) $_))
        PATTERN

        def_node_matcher :on_bad_map_to_h, <<~PATTERN
          ({send csend}
            (block
              ({send csend} _ {:map :collect})
              (args (arg $_el))
              (array (lvar _el) $_))
            :to_h)
        PATTERN

        def_node_matcher :on_bad_hash_brackets_map, <<~PATTERN
          (send
            (const _ :Hash)
            :[]
            (block
              ({send csend} _ {:map :collect})
              (args (arg $_el))
              (array (lvar _el) $_)))
        PATTERN

        private

        def new_method_name
          'index_with'
        end
      end
    end
  end
end
