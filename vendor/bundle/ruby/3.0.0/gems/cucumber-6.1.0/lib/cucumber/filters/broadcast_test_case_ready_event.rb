# frozen_string_literal: true

module Cucumber
  module Filters
    class BroadcastTestCaseReadyEvent < Core::Filter.new(:config)
      def test_case(test_case)
        config.notify :test_case_ready, test_case
        test_case.describe_to(receiver)
      end
    end
  end
end
