module Cucumber
  module Core
    module Test
      module Filters

        # This filter is used for testing Cucumber itself. It adds step definitions
        # that will activate steps to have passed / failed / pending results
        # if they use conventional names.
        #
        # It was extracted from our test code, and does not have any tests of its own.
        class ActivateStepsForSelfTest < Core::Filter.new
          Failure = Class.new(StandardError)

          def test_case(test_case)
            test_steps = test_case.test_steps.map do |step|
              case step.text
              when /fail/
                step.with_action { raise Failure }
              when /pending/
                step.with_action { raise Test::Result::Pending }
              when /pass/
                step.with_action {}
              else
                step
              end
            end

            test_case.with_steps(test_steps).describe_to(receiver)
          end
        end

      end
    end
  end
end
