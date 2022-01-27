# frozen_string_literal: true

require 'cucumber/core/filter'

module Cucumber
  module Filters
    class ApplyAfterStepHooks < Core::Filter.new(:hooks)
      def test_case(test_case)
        test_steps = hooks.find_after_step_hooks(test_case).apply(test_case.test_steps)
        test_case.with_steps(test_steps).describe_to(receiver)
      end
    end
  end
end
