# frozen_string_literal: true

module Cucumber
  class Runtime
    class AfterHooks
      def initialize(id_generator, hooks, scenario, event_bus)
        @hooks = hooks
        @scenario = scenario
        @id_generator = id_generator
        @event_bus = event_bus
      end

      def apply_to(test_case)
        test_case.with_steps(
          test_case.test_steps + after_hooks.reverse
        )
      end

      private

      def after_hooks
        @hooks.map do |hook|
          action = ->(result) { hook.invoke('After', @scenario.with_result(result)) }
          hook_step = Hooks.after_hook(@id_generator.new_id, hook.location, &action)
          @event_bus.hook_test_step_created(hook_step, hook)
          hook_step
        end
      end
    end
  end
end
