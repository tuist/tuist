# frozen_string_literal: true

module Cucumber
  module Glue
    module Snippet
      ARGUMENT_PATTERNS = ['"([^"]*)"', '(\d+)'].freeze

      class Generator
        def self.register_on(configuration)
          configuration.snippet_generators << new
        end

        def initialize(cucumber_expression_generator)
          @cucumber_expression_generator = cucumber_expression_generator
        end

        def call(code_keyword, step_name, multiline_arg, snippet_type)
          snippet_class = typed_snippet_class(snippet_type)
          snippet_class.new(@cucumber_expression_generator, code_keyword, step_name, multiline_arg).to_s
        end

        def typed_snippet_class(type)
          SNIPPET_TYPES.fetch(type || :cucumber_expression)
        end
      end

      class BaseSnippet
        def initialize(cucumber_expression_generator, code_keyword, step_name, multiline_argument)
          @number_of_arguments = 0
          @code_keyword = code_keyword
          @pattern = replace_and_count_capturing_groups(step_name)
          @generated_expressions = cucumber_expression_generator.generate_expressions(step_name)
          @multiline_argument = MultilineArgumentSnippet.new(multiline_argument)
        end

        def to_s
          "#{step} #{do_block}"
        end

        def step
          "#{code_keyword}#{typed_pattern}"
        end

        def self.cli_option_string(type, cucumber_expression_generator)
          format('%<type>-7s: %<description>-28s e.g. %<example>s', type: type, description: description, example: example(cucumber_expression_generator))
        end

        private

        attr_reader :code_keyword, :pattern, :generated_expressions, :multiline_argument, :number_of_arguments

        def replace_and_count_capturing_groups(pattern)
          modified_pattern = ::Regexp.escape(pattern).gsub('\ ', ' ').gsub('/', '\/')

          ARGUMENT_PATTERNS.each do |argument_pattern|
            modified_pattern.gsub!(::Regexp.new(argument_pattern), argument_pattern)
            @number_of_arguments += modified_pattern.scan(argument_pattern).length
          end

          modified_pattern
        end

        def do_block
          do_block = String.new # rubocop:disable Style/EmptyLiteral
          do_block << "do#{parameters}\n"
          multiline_argument.append_comment_to(do_block)
          do_block << "  pending # Write code here that turns the phrase above into concrete actions\n"
          do_block << 'end'
          do_block
        end

        def parameters
          block_args = (0...number_of_arguments).map { |n| "arg#{n + 1}" }
          multiline_argument.append_block_parameter_to(block_args)
          block_args.empty? ? '' : " |#{block_args.join(', ')}|"
        end

        class << self
          private

          def example(cucumber_expression_generator)
            new(cucumber_expression_generator, 'Given', 'I have 2 cukes', MultilineArgument::None.new).step
          end
        end
      end

      class CucumberExpression < BaseSnippet
        def typed_pattern
          "(\"#{generated_expressions[0].source}\")"
        end

        def to_s
          header = generated_expressions.each_with_index.map do |expr, i|
            prefix = i.zero? ? '' : '# '
            "#{prefix}#{code_keyword}('#{expr.source}') do#{parameters(expr)}"
          end.join("\n")

          body = String.new # rubocop:disable Style/EmptyLiteral
          multiline_argument.append_comment_to(body)
          body << "  pending # Write code here that turns the phrase above into concrete actions\n"
          body << 'end'

          "#{header}\n#{body}"
        end

        def parameters(expr)
          parameter_names = expr.parameter_names
          multiline_argument.append_block_parameter_to(parameter_names)
          parameter_names.empty? ? '' : " |#{parameter_names.join(', ')}|"
        end

        def self.description
          'Cucumber Expressions'
        end
      end

      class Regexp < BaseSnippet
        def typed_pattern
          "(/^#{pattern}$/)"
        end

        def self.description
          'Snippets with parentheses'
        end
      end

      class Classic < BaseSnippet
        def typed_pattern
          " /^#{pattern}$/"
        end

        def self.description
          'Snippets without parentheses. Note that these cause a warning from modern versions of Ruby.'
        end
      end

      class Percent < BaseSnippet
        def typed_pattern
          " %r{^#{pattern}$}"
        end

        def self.description
          'Snippets with percent regexp'
        end
      end

      SNIPPET_TYPES = {
        cucumber_expression: CucumberExpression,
        regexp: Regexp,
        classic: Classic,
        percent: Percent
      }.freeze

      module MultilineArgumentSnippet
        def self.new(multiline_argument)
          builder = Builder.new
          multiline_argument.describe_to(builder)
          builder.result
        end

        class Builder
          def doc_string(*_args)
            @result = DocString.new
          end

          def data_table(table, *_args)
            @result = DataTable.new(table)
          end

          def result
            @result || None.new
          end
        end

        class DocString
          def append_block_parameter_to(array)
            array << 'doc_string'
          end

          def append_comment_to(string); end
        end

        class DataTable
          def initialize(table)
            @table = table
          end

          def append_block_parameter_to(array)
            array << 'table'
          end

          def append_comment_to(string)
            string << "  # table is a #{Cucumber::MultilineArgument::DataTable}\n"
          end
        end

        class None
          def append_block_parameter_to(array); end

          def append_comment_to(string); end
        end
      end
    end
  end
end
