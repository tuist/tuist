# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop prevents usage of `"*"` on an Arel::Table column reference.
      #
      # Using `arel_table["*"]` causes the outputted string to be a literal
      # quoted asterisk (e.g. <tt>`my_model`.`*`</tt>). This causes the
      # database to look for a column named <tt>`*`</tt> (or `"*"`) as opposed
      # to expanding the column list as one would likely expect.
      #
      # @safety
      #   This cop's autocorrection is unsafe because it turns a quoted `*` into
      #   an SQL `*`, unquoted. `*` is a valid column name in certain databases
      #   supported by Rails, and even though it is usually a mistake,
      #   it might denote legitimate access to a column named `*`.
      #
      # @example
      #   # bad
      #   MyTable.arel_table["*"]
      #
      #   # good
      #   MyTable.arel_table[Arel.star]
      #
      class ArelStar < Base
        extend AutoCorrector

        MSG = 'Use `Arel.star` instead of `"*"` for expanded column lists.'

        RESTRICT_ON_SEND = %i[[]].freeze

        def_node_matcher :star_bracket?, <<~PATTERN
          (send {const (send _ :arel_table)} :[] $(str "*"))
        PATTERN

        def on_send(node)
          return unless (star = star_bracket?(node))

          add_offense(star) do |corrector|
            corrector.replace(star.loc.expression, 'Arel.star')
          end
        end
      end
    end
  end
end
