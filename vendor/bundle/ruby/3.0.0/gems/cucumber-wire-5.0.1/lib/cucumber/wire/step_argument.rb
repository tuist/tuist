# frozen_string_literal: true
require 'cucumber/cucumber_expressions/group'

module Cucumber
  module Wire
    # Defines the location and value of a captured argument from the step
    # text
    class StepArgument
      attr_reader :offset

      def initialize(offset, val)
        @offset, @value = offset, val
      end

      def value(_current_world)
        @value
      end

      def group
        CucumberExpressions::Group.new(@value, @offset, @offset + @value.length, [])
      end
    end
  end
end
