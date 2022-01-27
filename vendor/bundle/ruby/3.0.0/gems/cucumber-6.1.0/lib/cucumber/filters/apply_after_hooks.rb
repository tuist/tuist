# frozen_string_literal: true

module Cucumber
  module Filters
    class ApplyAfterHooks < Core::Filter.new(:hooks)
      def test_case(test_case)
        hooks.apply_after_hooks(test_case).describe_to(receiver)
      end
    end
  end
end
