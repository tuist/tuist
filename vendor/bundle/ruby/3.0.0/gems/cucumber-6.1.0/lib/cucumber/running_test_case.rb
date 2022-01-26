# frozen_string_literal: true

require 'delegate'

module Cucumber
  # Represents the current status of a running test case.
  #
  # This wraps a `Cucumber::Core::Test::Case` and delegates
  # many methods to that object.
  #
  # We decorete the core object with the current result.
  # In the first Before hook of a scenario, this will be an
  # instance of `Cucumber::Core::Test::Result::Unknown`
  # but as the scenario runs, it will be updated to reflect
  # the passed / failed / undefined / skipped status of
  # the test case.
  #
  module RunningTestCase
    def self.new(test_case)
      TestCase.new(test_case)
    end

    class TestCase < SimpleDelegator
      def initialize(test_case, result = Core::Test::Result::Unknown.new)
        @test_case = test_case
        @result = result
        super test_case
      end

      def accept_hook?(hook)
        hook.tag_expressions.all? { |expression| @test_case.match_tags?(expression) }
      end

      def exception
        return unless @result.failed?
        @result.exception
      end

      def status
        @result.to_sym
      end

      def failed?
        @result.failed?
      end

      def passed?
        !failed?
      end

      def source_tag_names
        tags.map &:name
      end

      def with_result(result)
        self.class.new(@test_case, result)
      end
    end
  end
end
