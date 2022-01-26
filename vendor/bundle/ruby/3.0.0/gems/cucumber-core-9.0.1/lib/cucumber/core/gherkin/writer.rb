# frozen_string_literal: true
require 'cucumber/core/gherkin/writer/helpers'
require 'cucumber/core/gherkin/document'

module Cucumber
  module Core
    module Gherkin

      module Writer
        NEW_LINE = ''
        def gherkin(uri = nil, &source)
          uri ||= 'features/test.feature'
          builder = Gherkin.new(uri, &source)
          builder.build
        end

        class Gherkin
          def initialize(uri, &source)
            @uri, @source = uri, source
          end

          def comment(line)
            comment_lines << "# #{line}"
          end

          def comment_lines
            @comment_lines ||= []
          end

          def feature(*args, &source)
            @feature = Feature.new(comment_lines, *args).tap do |builder|
              builder.instance_exec(&source) if source
            end
            self
          end

          def build
            instance_exec(&@source)
            Document.new(@uri, @feature.build.join("\n"))
          end
        end

        class Feature
          include HasElements
          include HasOptionsInitializer
          include HasDescription
          include Indentation.level(0)

          default_keyword 'Feature'

          elements :background, :rule, :scenario, :scenario_outline

          def build(source = [])
            elements.inject(source + statements) { |acc, el| el.build(acc) + [NEW_LINE] }
          end

          private
          def language
            options[:language]
          end

          def statements
            prepare_statements(
              language_statement,
              comments_statement,
              tag_statement,
              name_statement,
              description_statement,
              NEW_LINE
            )
          end

          def language_statement
            "# language: #{language}" if language
          end
        end

        class Background
          include HasElements
          include HasOptionsInitializer
          include HasDescription
          include Indentation.level 2

          default_keyword 'Background'

          elements :step

          private
          def statements
            prepare_statements(
              comments_statement,
              tag_statement,
              name_statement,
              description_statement
            )
          end
        end

        class Rule
          include HasElements
          include HasOptionsInitializer
          include HasDescription
          include Indentation.level 2

          default_keyword 'Rule'

          elements :example, :scenario

          private
          def statements
            prepare_statements(
              comments_statement,
              name_statement,
              description_statement,
              NEW_LINE
            )
          end
        end

        class Scenario
          include HasElements
          include HasOptionsInitializer
          include HasDescription
          include Indentation.level 2

          default_keyword 'Scenario'

          elements :step

          private
          def statements
            prepare_statements(
              comments_statement,
              tag_statement,
              name_statement,
              description_statement
            )
          end
        end

        class Example < Scenario
          include Indentation.level 4

          default_keyword 'Example'
        end

        class ScenarioOutline
          include HasElements
          include HasOptionsInitializer
          include HasDescription
          include Indentation.level 2

          default_keyword 'Scenario Outline'

          elements :step, :examples

          private
          def statements
            prepare_statements comments_statement, tag_statement, name_statement, description_statement
          end
        end

        class Step
          include HasElements
          include HasOptionsInitializer
          include Indentation.level 4

          default_keyword 'Given'

          elements :table

          def doc_string(string, content_type='')
            elements << DocString.new(string, content_type)
          end

          private
          def statements
            prepare_statements comments_statement, name_statement
          end

          def name_statement
            "#{keyword} #{name}"
          end
        end

        class Table
          include Indentation.level(6)
          include HasRows

          def initialize(*)
          end

          def build(source)
            source + statements
          end

          private
          def statements
            row_statements
          end
        end

        class DocString
          include Indentation.level(6)

          attr_reader :strings, :content_type
          private :strings, :content_type

          def initialize(string, content_type)
            @strings = string.split("\n").map(&:strip)
            @content_type = content_type
          end

          def build(source)
            source + statements
          end

          private
          def statements
            prepare_statements doc_string_statement
          end

          def doc_string_statement
            [
              %["""#{content_type}],
              strings,
              '"""'
            ]
          end
        end

        class Examples
          include HasOptionsInitializer
          include HasRows
          include HasDescription
          include Indentation.level(4)

          default_keyword 'Examples'

          def build(source)
            source + statements
          end

          private
          def statements
            prepare_statements(
              NEW_LINE,
              comments_statement,
              tag_statement,
              name_statement,
              description_statement,
              row_statements(2)
            )
          end
        end
      end
    end
  end
end
