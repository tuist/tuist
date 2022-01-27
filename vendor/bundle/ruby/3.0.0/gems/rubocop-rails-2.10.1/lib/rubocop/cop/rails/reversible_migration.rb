# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks whether the change method of the migration file is
      # reversible.
      #
      # @example
      #   # bad
      #   def change
      #     change_table :users do |t|
      #       t.remove :name
      #     end
      #   end
      #
      #   # good
      #   def change
      #     create_table :users do |t|
      #       t.string :name
      #     end
      #   end
      #
      #   # good
      #   def change
      #     reversible do |dir|
      #       change_table :users do |t|
      #         dir.up do
      #           t.column :name, :string
      #         end
      #
      #         dir.down do
      #           t.remove :name
      #         end
      #       end
      #     end
      #   end
      #
      # @example
      #   # drop_table
      #
      #   # bad
      #   def change
      #     drop_table :users
      #   end
      #
      #   # good
      #   def change
      #     drop_table :users do |t|
      #       t.string :name
      #     end
      #   end
      #
      # @example
      #   # change_column_default
      #
      #   # bad
      #   def change
      #     change_column_default(:suppliers, :qualification, 'new')
      #   end
      #
      #   # good
      #   def change
      #     change_column_default(:posts, :state, from: nil, to: "draft")
      #   end
      #
      # @example
      #   # remove_column
      #
      #   # bad
      #   def change
      #     remove_column(:suppliers, :qualification)
      #   end
      #
      #   # good
      #   def change
      #     remove_column(:suppliers, :qualification, :string)
      #   end
      #
      # @example
      #   # remove_foreign_key
      #
      #   # bad
      #   def change
      #     remove_foreign_key :accounts, column: :owner_id
      #   end
      #
      #   # good
      #   def change
      #     remove_foreign_key :accounts, :branches
      #   end
      #
      #   # good
      #   def change
      #     remove_foreign_key :accounts, to_table: :branches
      #   end
      #
      # @example
      #   # change_table
      #
      #   # bad
      #   def change
      #     change_table :users do |t|
      #       t.remove :name
      #       t.change_default :authorized, 1
      #       t.change :price, :string
      #     end
      #   end
      #
      #   # good
      #   def change
      #     change_table :users do |t|
      #       t.string :name
      #     end
      #   end
      #
      #   # good
      #   def change
      #     reversible do |dir|
      #       change_table :users do |t|
      #         dir.up do
      #           t.change :price, :string
      #         end
      #
      #         dir.down do
      #           t.change :price, :integer
      #         end
      #       end
      #     end
      #   end
      #
      # @example
      #   # remove_columns
      #
      #   # bad
      #   def change
      #     remove_columns :users, :name, :email
      #   end
      #
      #   # good
      #   def change
      #     reversible do |dir|
      #       dir.up do
      #         remove_columns :users, :name, :email
      #       end
      #
      #       dir.down do
      #         add_column :users, :name, :string
      #         add_column :users, :email, :string
      #       end
      #     end
      #   end
      #
      #   # good (Rails >= 6.1, see https://github.com/rails/rails/pull/36589)
      #   def change
      #     remove_columns :users, :name, :email, type: :string
      #   end
      #
      # @example
      #   # remove_index
      #
      #   # bad
      #   def change
      #     remove_index :users, name: :index_users_on_email
      #   end
      #
      #   # good
      #   def change
      #     remove_index :users, :email
      #   end
      #
      #   # good
      #   def change
      #     remove_index :users, column: :email
      #   end
      #
      # @see https://api.rubyonrails.org/classes/ActiveRecord/Migration/CommandRecorder.html
      class ReversibleMigration < Base
        MSG = '%<action>s is not reversible.'

        def_node_matcher :irreversible_schema_statement_call, <<~PATTERN
          (send nil? ${:execute :remove_belongs_to} ...)
        PATTERN

        def_node_matcher :drop_table_call, <<~PATTERN
          (send nil? :drop_table ...)
        PATTERN

        def_node_matcher :remove_column_call, <<~PATTERN
          (send nil? :remove_column $...)
        PATTERN

        def_node_matcher :remove_foreign_key_call, <<~PATTERN
          (send nil? :remove_foreign_key _ $_)
        PATTERN

        def_node_matcher :change_table_call, <<~PATTERN
          (send nil? :change_table $_ ...)
        PATTERN

        def_node_matcher :remove_columns_call, <<~PATTERN
          (send nil? :remove_columns ... $_)
        PATTERN

        def_node_matcher :remove_index_call, <<~PATTERN
          (send nil? :remove_index _ $_)
        PATTERN

        def on_send(node)
          return unless within_change_method?(node)
          return if within_reversible_or_up_only_block?(node)

          check_irreversible_schema_statement_node(node)
          check_drop_table_node(node)
          check_reversible_hash_node(node)
          check_remove_column_node(node)
          check_remove_foreign_key_node(node)
          check_remove_columns_node(node)
          check_remove_index_node(node)
        end

        def on_block(node)
          return unless within_change_method?(node)
          return if within_reversible_or_up_only_block?(node)
          return if node.body.nil?

          check_change_table_node(node.send_node, node.body)
        end

        private

        def check_irreversible_schema_statement_node(node)
          irreversible_schema_statement_call(node) do |method_name|
            add_offense(node, message: format(MSG, action: method_name))
          end
        end

        def check_drop_table_node(node)
          drop_table_call(node) do
            unless node.parent.block_type? || node.last_argument.block_pass_type?
              add_offense(
                node,
                message: format(MSG, action: 'drop_table(without block)')
              )
            end
          end
        end

        def check_reversible_hash_node(node)
          return if reversible_change_table_call?(node)

          add_offense(
            node,
            message: format(
              MSG, action: "#{node.method_name}(without :from and :to)"
            )
          )
        end

        def check_remove_column_node(node)
          remove_column_call(node) do |args|
            if args.to_a.size < 3
              add_offense(
                node,
                message: format(MSG, action: 'remove_column(without type)')
              )
            end
          end
        end

        def check_remove_foreign_key_node(node)
          remove_foreign_key_call(node) do |arg|
            if arg.hash_type? && !all_hash_key?(arg, :to_table)
              add_offense(node, message: format(MSG, action: 'remove_foreign_key(without table)'))
            end
          end
        end

        def check_change_table_node(node, block)
          change_table_call(node) do |arg|
            if block.send_type?
              check_change_table_offense(arg, block)
            else
              block.each_child_node(:send) do |child_node|
                check_change_table_offense(arg, child_node)
              end
            end
          end
        end

        def check_remove_columns_node(node)
          remove_columns_call(node) do |args|
            unless all_hash_key?(args, :type) && target_rails_version >= 6.1
              action = target_rails_version >= 6.1 ? 'remove_columns(without type)' : 'remove_columns'

              add_offense(
                node,
                message: format(MSG, action: action)
              )
            end
          end
        end

        def check_remove_index_node(node)
          remove_index_call(node) do |args|
            if args.hash_type? && !all_hash_key?(args, :column)
              add_offense(
                node,
                message: format(MSG, action: 'remove_index(without column)')
              )
            end
          end
        end

        def check_change_table_offense(receiver, node)
          method_name = node.method_name
          return if receiver != node.receiver &&
                    reversible_change_table_call?(node)

          add_offense(
            node,
            message: format(MSG, action: "change_table(with #{method_name})")
          )
        end

        def reversible_change_table_call?(node)
          case node.method_name
          when :change, :remove
            false
          when :change_default, :change_column_default, :change_table_comment,
               :change_column_comment
            all_hash_key?(node.arguments.last, :from, :to)
          else
            true
          end
        end

        def within_change_method?(node)
          node.each_ancestor(:def).any? do |ancestor|
            ancestor.method?(:change)
          end
        end

        def within_reversible_or_up_only_block?(node)
          node.each_ancestor(:block).any? do |ancestor|
            ancestor.block_type? &&
              ancestor.send_node.method?(:reversible) ||
              ancestor.send_node.method?(:up_only)
          end
        end

        def all_hash_key?(args, *keys)
          return false unless args&.hash_type?

          hash_keys = args.keys.map do |key|
            key.children.first.to_sym
          end

          (hash_keys & keys).sort == keys
        end
      end
    end
  end
end
