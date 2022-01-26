# frozen_string_literal: true
module Cucumber
  module Core
    module Gherkin
      module Writer

        module HasOptionsInitializer
          def self.included(base)
            base.extend HasDefaultKeyword
          end

          attr_reader :name, :options
          private :name, :options

          def initialize(*args)
            @comments = args.shift if args.first.is_a?(Array)
            @comments ||= []
            @options = args.pop if args.last.is_a?(Hash)
            @options ||= {}
            @name = args.first
          end

          private

          def comments_statement
            @comments
          end

          def keyword
            options.fetch(:keyword) { self.class.keyword }
          end

          def name_statement
            "#{keyword}: #{name}".strip
          end

          def tag_statement
            tags
          end

          def tags
            options[:tags]
          end

          module HasDefaultKeyword
            def default_keyword(keyword)
              @keyword = keyword
            end

            def keyword
              @keyword
            end
          end
        end

        module AcceptsComments
          def comment(line)
            comment_lines << "# #{line}"
          end

          def comment_lines
            @comment_lines ||= []
          end

          def slurp_comments
            comment_lines.tap { @comment_lines = nil }
          end
        end

        module HasElements
          include AcceptsComments

          def self.included(base)
            base.extend HasElementBuilders
          end

          def build(source = [])
            elements.inject(source + statements) { |acc, el| el.build(acc) }
          end

          private
          def elements
            @elements ||= []
          end

          module HasElementBuilders
            def elements(*names)
              names.each { |name| element(name) }
            end

            private
            def element(name)
              define_method name do |*args, &source|
                factory_name = String(name).split("_").map(&:capitalize).join
                factory = Writer.const_get(factory_name)
                factory.new(slurp_comments, *args).tap do |builder|
                  builder.instance_exec(&source) if source
                  elements << builder
                end
                self
              end
            end
          end
        end

        module Indentation
          def self.level(number)
            Module.new do
              define_method :indent do |string, amount=nil|
                amount ||= number
                return string if string.nil? || string.empty?
                (' ' * amount) + string
              end

              define_method :indent_level do
                number
              end

              define_method :prepare_statements do |*statements|
                statements.flatten.compact.map { |s| indent(s) }
              end
            end
          end
        end

        module HasDescription
          private
          def description
            options.fetch(:description, '').split("\n").map(&:strip)
          end

          def description_statement
            description.map { |s| indent(s, 2) } unless description.empty?
          end
        end

        module HasRows
          def row(*cells)
            rows << cells
          end

          def rows
            @rows ||= []
          end

          private

          def row_statements(indent=nil)
            rows.map { |row| indent(table_row(row), indent) }
          end

          def table_row(row)
            padded = pad(row)
            "| #{padded.join(' | ')} |"
          end

          def pad(row)
            row.map.with_index { |text, position| justify_cell(text, position) }
          end

          def column_length(column)
            lengths = rows.transpose.map { |r| r.map(&:length).max }
            lengths[column]
          end

          def justify_cell(cell, position)
            cell.ljust(column_length(position))
          end
        end
      end

    end
  end
end
