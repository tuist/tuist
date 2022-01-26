# frozen_string_literal: true
require 'cucumber/core/filter'

module Cucumber
  module Core
    module Test
      class TagFilter < Filter.new(:filter_expressions)

        def test_case(test_case)
          test_cases << test_case
          if test_case.match_tags?(filter_expressions)
            test_case.describe_to(receiver)
          end
          self
        end

        def done
          receiver.done
          self
        end

        private

        def test_cases
          @test_cases ||= TestCases.new
        end

        class TestCases
          attr_reader :test_cases_by_tag_name
          private :test_cases_by_tag_name
          def initialize
            @test_cases_by_tag_name = Hash.new { [] }
          end

          def <<(test_case)
            test_case.tags.each do |tag|
              test_cases_by_tag_name[tag.name] += [test_case]
            end
            self
          end

          def with_tag_name(tag_name)
            test_cases_by_tag_name[tag_name]
          end
        end
      end
    end
  end
end
