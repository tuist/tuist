# frozen_string_literal: true

module Cucumber
  module Filters
    class ApplyBeforeHooks < Core::Filter.new(:hooks)
      def test_case(test_case)
        hooks.apply_before_hooks(test_case).describe_to(receiver)
      end
    end
  end
end
