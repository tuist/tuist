# frozen_string_literal: true

module RuboCop
  module Rails
    module SchemaLoader
      # Represent db/schema.rb
      class Schema
        attr_reader :tables, :add_indicies

        def initialize(ast)
          @tables = []
          @add_indicies = []

          build!(ast)
        end

        def table_by(name:)
          tables.find do |table|
            table.name == name
          end
        end

        def add_indicies_by(table_name:)
          add_indicies.select do |add_index|
            add_index.table_name == table_name
          end
        end

        private

        def build!(ast)
          raise "Unexpected type: #{ast.type}" unless ast.block_type?

          each_table(ast) do |table_def|
            @tables << Table.new(table_def)
          end

          # Compatibility for Rails 4.2.
          each_add_index(ast) do |add_index_def|
            @add_indicies << AddIndex.new(add_index_def)
          end
        end

        def each_table(ast)
          case ast.body.type
          when :begin
            ast.body.children.each do |node|
              next unless node.block_type? && node.method?(:create_table)

              yield(node)
            end
          else
            yield ast.body
          end
        end

        def each_add_index(ast)
          ast.body.children.each do |node|
            next if !node&.send_type? || !node.method?(:add_index)

            yield(node)
          end
        end
      end

      # Represent a table
      class Table
        attr_reader :name, :columns, :indices

        def initialize(node)
          @name = node.send_node.first_argument.value
          @columns = build_columns(node)
          @indices = build_indices(node)
        end

        def with_column?(name:)
          @columns.any? { |c| c.name == name }
        end

        private

        def build_columns(node)
          each_content(node).map do |child|
            next unless child&.send_type?
            next if child.method?(:index)

            Column.new(child)
          end.compact
        end

        def build_indices(node)
          each_content(node).map do |child|
            next unless child&.send_type?
            next unless child.method?(:index)

            Index.new(child)
          end.compact
        end

        def each_content(node, &block)
          return enum_for(__method__, node) unless block

          case node.body&.type
          when :begin
            node.body.children.each(&block)
          else
            yield(node.body)
          end
        end
      end

      # Represent a column
      class Column
        attr_reader :name, :type, :not_null

        def initialize(node)
          @name = node.first_argument.str_content
          @type = node.method_name
          @not_null = nil

          analyze_keywords!(node)
        end

        private

        def analyze_keywords!(node)
          pairs = node.arguments.last
          return unless pairs.hash_type?

          pairs.each_pair do |k, v|
            @not_null = !v.true_type? if k.value == :null
          end
        end
      end

      # Represent an index
      class Index
        attr_reader :name, :columns, :expression, :unique

        def initialize(node)
          @columns, @expression = build_columns_or_expr(node.first_argument)
          @unique = nil

          analyze_keywords!(node)
        end

        private

        def build_columns_or_expr(columns)
          if columns.array_type?
            [columns.values.map(&:value), nil]
          else
            [[], columns.value]
          end
        end

        def analyze_keywords!(node)
          pairs = node.arguments.last
          return unless pairs.hash_type?

          pairs.each_pair do |k, v|
            case k.value
            when :name
              @name = v.value
            when :unique
              @unique = true
            end
          end
        end
      end

      # Represent an `add_index`
      class AddIndex < Index
        attr_reader :table_name

        def initialize(node)
          super(node)

          @table_name = node.first_argument.value
          @columns, @expression = build_columns_or_expr(node.arguments[1])
          @unique = nil

          analyze_keywords!(node)
        end
      end
    end
  end
end
