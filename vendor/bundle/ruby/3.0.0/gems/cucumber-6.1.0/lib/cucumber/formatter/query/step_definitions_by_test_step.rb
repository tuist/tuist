require 'cucumber/formatter/errors'

module Cucumber
  module Formatter
    module Query
      class StepDefinitionsByTestStep
        def initialize(config)
          @step_definition_ids_by_test_step_id = {}
          @step_match_arguments_by_test_step_id = {}

          config.on_event :test_step_created, &method(:on_test_step_created)
          config.on_event :step_activated, &method(:on_step_activated)
        end

        def step_definition_ids(test_step)
          return @step_definition_ids_by_test_step_id[test_step.id] if @step_definition_ids_by_test_step_id.key?(test_step.id)

          raise TestStepUnknownError, "No step definition found for #{test_step.id} }. Known: #{@step_definition_ids_by_test_step_id.keys}"
        end

        def step_match_arguments(test_step)
          return @step_match_arguments_by_test_step_id[test_step.id] if @step_match_arguments_by_test_step_id.key?(test_step.id)

          raise TestStepUnknownError, "No step match arguments found for #{test_step.id} }. Known: #{@step_match_arguments_by_test_step_id.keys}"
        end

        private

        def on_test_step_created(event)
          @step_definition_ids_by_test_step_id[event.test_step.id] = []
        end

        def on_step_activated(event)
          @step_definition_ids_by_test_step_id[event.test_step.id] << event.step_match.step_definition.id
          @step_match_arguments_by_test_step_id[event.test_step.id] = event.step_match.step_arguments
        end
      end
    end
  end
end
