# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop suggests you remove a column that does not exist in the schema from `ignored_columns`.
      # `ignored_columns` is necessary to drop a column from RDBMS, but you don't need it after the migration
      # to drop the column. You avoid forgetting to remove `ignored_columns` by this cop.
      #
      # @example
      #   # bad
      #   class User < ApplicationRecord
      #     self.ignored_columns = [:already_removed_column]
      #   end
      #
      #   # good
      #   class User < ApplicationRecord
      #     self.ignored_columns = [:still_existing_column]
      #   end
      #
      class UnusedIgnoredColumns < Base
        include ActiveRecordHelper

        MSG = 'Remove `%<column_name>s` from `ignored_columns` because the column does not exist.'
        RESTRICT_ON_SEND = %i[ignored_columns=].freeze

        def_node_matcher :ignored_columns, <<~PATTERN
          (send self :ignored_columns= $array)
        PATTERN

        def_node_matcher :column_name, <<~PATTERN
          ({str sym} $_)
        PATTERN

        def on_send(node)
          return unless (columns = ignored_columns(node))
          return unless schema

          table = table(node)
          return unless table

          columns.children.each do |column_node|
            check_column_existence(column_node, table)
          end
        end

        private

        def check_column_existence(column_node, table)
          column_name = column_name(column_node)
          return unless column_name
          return if table.with_column?(name: column_name.to_s)

          message = format(MSG, column_name: column_name)
          add_offense(column_node, message: message)
        end

        def class_node(node)
          node.each_ancestor.find(&:class_type?)
        end

        def table(node)
          klass = class_node(node)
          schema.table_by(name: table_name(klass))
        end
      end
    end
  end
end
