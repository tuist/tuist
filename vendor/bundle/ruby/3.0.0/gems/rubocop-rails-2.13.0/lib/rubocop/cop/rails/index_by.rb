# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop looks for uses of `each_with_object({}) { ... }`,
      # `map { ... }.to_h`, and `Hash[map { ... }]` that are transforming
      # an enumerable into a hash where the values are the original elements.
      # Rails provides the `index_by` method for this purpose.
      #
      # @example
      #   # bad
      #   [1, 2, 3].each_with_object({}) { |el, h| h[foo(el)] = el }
      #   [1, 2, 3].to_h { |el| [foo(el), el] }
      #   [1, 2, 3].map { |el| [foo(el), el] }.to_h
      #   Hash[[1, 2, 3].collect { |el| [foo(el), el] }]
      #
      #   # good
      #   [1, 2, 3].index_by { |el| foo(el) }
      class IndexBy < Base
        include IndexMethod
        extend AutoCorrector

        def_node_matcher :on_bad_each_with_object, <<~PATTERN
          (block
            ({send csend} _ :each_with_object (hash))
            (args (arg $_el) (arg _memo))
            ({send csend} (lvar _memo) :[]= $!`_memo (lvar _el)))
        PATTERN

        def_node_matcher :on_bad_to_h, <<~PATTERN
          (block
            ({send csend} _ :to_h)
            (args (arg $_el))
            (array $_ (lvar _el)))
        PATTERN

        def_node_matcher :on_bad_map_to_h, <<~PATTERN
          ({send csend}
            (block
              ({send csend} _ {:map :collect})
              (args (arg $_el))
              (array $_ (lvar _el)))
            :to_h)
        PATTERN

        def_node_matcher :on_bad_hash_brackets_map, <<~PATTERN
          (send
            (const _ :Hash)
            :[]
            (block
              ({send csend} _ {:map :collect})
              (args (arg $_el))
              (array $_ (lvar _el))))
        PATTERN

        private

        def new_method_name
          'index_by'
        end
      end
    end
  end
end
