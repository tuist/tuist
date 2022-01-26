# frozen_string_literal: true
require 'cucumber/core/filter'

module Cucumber
  module Core
    module Test

      # Sorts and filters scenarios based on a list of locations
      class LocationsFilter < Filter.new(:filter_locations)

        def test_case(test_case)
          test_cases[test_case.location.file] << test_case
          self
        end

        def done
          sorted_test_cases.each do |test_case|
            test_case.describe_to receiver
          end
          receiver.done
          self
        end

        private

        def sorted_test_cases
          filter_locations.map { |filter_location|
            test_cases[filter_location.file].select { |test_case|
              filter_location.match?(test_case.location)
            }
          }.flatten.uniq
        end

        def test_cases
          @test_cases ||= Hash.new { |hash, key| hash[key] = [] }
        end
      end
    end
  end
end
