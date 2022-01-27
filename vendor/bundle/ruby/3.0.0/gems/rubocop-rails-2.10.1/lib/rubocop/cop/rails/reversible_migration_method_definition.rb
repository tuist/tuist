# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks whether the migration implements
      # either a `change` method or both an `up` and a `down`
      # method.
      #
      # @example
      #   # bad
      #   class SomeMigration < ActiveRecord::Migration[6.0]
      #     def up
      #       # up migration
      #     end
      #
      #     # <----- missing down method
      #   end
      #
      #   class SomeMigration < ActiveRecord::Migration[6.0]
      #     # <----- missing up method
      #
      #     def down
      #       # down migration
      #     end
      #   end
      #
      #   # good
      #   class SomeMigration < ActiveRecord::Migration[6.0]
      #     def change
      #       # reversible migration
      #     end
      #   end
      #
      #   # good
      #   class SomeMigration < ActiveRecord::Migration[6.0]
      #     def up
      #       # up migration
      #     end
      #
      #     def down
      #       # down migration
      #     end
      #   end
      class ReversibleMigrationMethodDefinition < Base
        MSG = 'Migrations must contain either a `change` method, or ' \
              'both an `up` and a `down` method.'

        def_node_matcher :migration_class?, <<~PATTERN
          (class
            (const nil? _)
            (send
              (const (const nil? :ActiveRecord) :Migration)
              :[]
              (float _))
            _)
        PATTERN

        def_node_matcher :change_method?, <<~PATTERN
          [ #migration_class? `(def :change (args) _) ]
        PATTERN

        def_node_matcher :up_and_down_methods?, <<~PATTERN
          [ #migration_class? `(def :up (args) _) `(def :down (args) _) ]
        PATTERN

        def on_class(node)
          return if change_method?(node) || up_and_down_methods?(node)

          add_offense(node)
        end
      end
    end
  end
end
