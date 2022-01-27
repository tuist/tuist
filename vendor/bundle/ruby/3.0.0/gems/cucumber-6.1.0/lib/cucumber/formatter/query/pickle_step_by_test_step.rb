require 'cucumber/formatter/errors'

module Cucumber
  module Formatter
    module Query
      class PickleStepByTestStep
        def initialize(config)
          @pickle_id_step_by_test_step_id = {}
          config.on_event :test_step_created, &method(:on_test_step_created)
        end

        def pickle_step_id(test_step)
          return @pickle_id_step_by_test_step_id[test_step.id] if @pickle_id_step_by_test_step_id.key?(test_step.id)

          raise TestStepUnknownError, "No pickle step found for #{test_step.id} }. Known: #{@pickle_id_step_by_test_step_id.keys}"
        end

        private

        def on_test_step_created(event)
          @pickle_id_step_by_test_step_id[event.test_step.id] = event.pickle_step.id
        end
      end
    end
  end
end
