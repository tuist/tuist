require 'cucumber/formatter/errors'

module Cucumber
  module Formatter
    module Query
      class TestCaseStartedByTestCase
        def initialize(config)
          @config = config
          config.on_event :test_case_created, &method(:on_test_case_created)
          config.on_event :test_case_started, &method(:on_test_case_started)

          @attempts_by_test_case_id = {}
          @test_case_started_id_by_test_case_id = {}
        end

        def attempt_by_test_case(test_case)
          raise TestCaseUnknownError, "No test case found for #{test_case.id} }. Known: #{@attempts_by_test_case_id.keys}" unless @attempts_by_test_case_id.key?(test_case.id)
          @attempts_by_test_case_id[test_case.id]
        end

        def test_case_started_id_by_test_case(test_case)
          raise TestCaseUnknownError, "No test case found for #{test_case.id} }. Known: #{@test_case_started_id_by_test_case_id.keys}" unless @test_case_started_id_by_test_case_id.key?(test_case.id)
          @test_case_started_id_by_test_case_id[test_case.id]
        end

        private

        def on_test_case_created(event)
          @attempts_by_test_case_id[event.test_case.id] = 0
          @test_case_started_id_by_test_case_id[event.test_case.id] = nil
        end

        def on_test_case_started(event)
          @attempts_by_test_case_id[event.test_case.id] += 1
          @test_case_started_id_by_test_case_id[event.test_case.id] = @config.id_generator.new_id
        end
      end
    end
  end
end
