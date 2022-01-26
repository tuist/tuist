require 'cucumber/formatter/errors'

module Cucumber
  module Formatter
    module Query
      class HookByTestStep
        def initialize(config)
          @hook_id_by_test_step_id = {}

          config.on_event :test_step_created, &method(:on_test_step_created)
          config.on_event :hook_test_step_created, &method(:on_hook_test_step_created)
        end

        def hook_id(test_step)
          return @hook_id_by_test_step_id[test_step.id] if @hook_id_by_test_step_id.key?(test_step.id)
          raise TestStepUnknownError, "No hook found for #{test_step.id} }. Known: #{@hook_id_by_test_step_id.keys}"
        end

        private

        def on_test_step_created(event)
          @hook_id_by_test_step_id[event.test_step.id] = nil
        end

        def on_hook_test_step_created(event)
          @hook_id_by_test_step_id[event.test_step.id] = event.hook.id
        end
      end
    end
  end
end
