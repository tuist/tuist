# frozen_string_literal: true

module Cucumber
  module Filters
    class GatedReceiver
      def initialize(receiver)
        @receiver = receiver
        @test_cases = []
      end

      def test_case(test_case)
        @test_cases << test_case
        self
      end

      def done
        @test_cases.map do |test_case|
          test_case.describe_to(@receiver)
        end
        @receiver.done
        self
      end
    end
  end
end
