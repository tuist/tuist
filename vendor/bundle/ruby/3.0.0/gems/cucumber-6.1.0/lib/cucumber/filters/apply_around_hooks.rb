# frozen_string_literal: true

require 'cucumber/core/filter'

module Cucumber
  module Filters
    class ApplyAroundHooks < Core::Filter.new(:hooks)
      def test_case(test_case)
        around_hooks = hooks.find_around_hooks(test_case)
        test_case.with_around_hooks(around_hooks).describe_to(receiver)
      end
    end
  end
end
