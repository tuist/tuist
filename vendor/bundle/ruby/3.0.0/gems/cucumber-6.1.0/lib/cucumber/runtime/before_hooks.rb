# frozen_string_literal: true

require 'cucumber/hooks'

module Cucumber
  class Runtime
    class BeforeHooks
      def initialize(id_generator, hooks, scenario, event_bus)
        @hooks = hooks
        @scenario = scenario
        @id_generator = id_generator
        @event_bus = event_bus
      end

      def apply_to(test_case)
        test_case.with_steps(
          before_hooks + test_case.test_steps
        )
      end

      private

      def before_hooks
        @hooks.map do |hook|
          action_block = ->(result) { hook.invoke('Before', @scenario.with_result(result)) }
          hook_step = Hooks.before_hook(@id_generator.new_id, hook.location, &action_block)
          @event_bus.hook_test_step_created(hook_step, hook)
          hook_step
        end
      end
    end
  end
end
