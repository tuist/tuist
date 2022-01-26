# frozen_string_literal: true

require 'cucumber/formatter/io'
require 'cucumber/formatter/console'

module Cucumber
  module Formatter
    class FailFast
      def initialize(configuration)
        @previous_test_case = nil
        configuration.on_event :test_case_finished do |event|
          test_case, result = *event.attributes
          if test_case != @previous_test_case
            @previous_test_case = event.test_case
            Cucumber.wants_to_quit = true unless result.ok?(configuration.strict)
          elsif result.passed?
            Cucumber.wants_to_quit = false
          end
        end
      end
    end
  end
end
