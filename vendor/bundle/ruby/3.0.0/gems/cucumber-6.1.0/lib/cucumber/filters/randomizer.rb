# frozen_string_literal: true

require 'digest/sha2'

module Cucumber
  module Filters
    # Batches up all test cases, randomizes them, and then sends them on
    class Randomizer
      def initialize(seed, receiver = nil)
        @receiver = receiver
        @test_cases = []
        @seed = seed
      end

      def test_case(test_case)
        @test_cases << test_case
        self
      end

      def done
        shuffled_test_cases.each do |test_case|
          test_case.describe_to(@receiver)
        end
        @receiver.done
        self
      end

      def with_receiver(receiver)
        self.class.new(@seed, receiver)
      end

      private

      def shuffled_test_cases
        digester = Digest::SHA2.new(256)
        @test_cases.map.with_index
                   .sort_by { |_, index| digester.digest((@seed + index).to_s) }
                   .map { |test_case, _| test_case }
      end

      attr_reader :seed
      private :seed
    end
  end
end
