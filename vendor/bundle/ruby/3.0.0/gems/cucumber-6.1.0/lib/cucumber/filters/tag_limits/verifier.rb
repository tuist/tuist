# frozen_string_literal: true

module Cucumber
  module Filters
    class TagLimits
      class Verifier
        def initialize(tag_limits)
          @tag_limits = tag_limits
        end

        def verify!(test_case_index)
          breaches = collect_breaches(test_case_index)
          raise TagLimitExceededError.new(*breaches) unless breaches.empty?
        end

        private

        def collect_breaches(test_case_index)
          tag_limits.reduce([]) do |breaches, (tag_name, limit)|
            breaches.tap do |breach|
              breach << Breach.new(tag_name, limit, test_case_index.locations_of_tag_name(tag_name)) if test_case_index.count_by_tag_name(tag_name) > limit
            end
          end
        end

        attr_reader :tag_limits

        class Breach
          INDENT = (' ' * 2).freeze

          def initialize(tag_name, limit, locations)
            @tag_name = tag_name
            @limit = limit
            @locations = locations
          end

          def to_s
            [
              "#{tag_name} occurred #{tag_count} times, but the limit was set to #{limit}",
              *locations.map(&:to_s)
            ].join("\n#{INDENT}")
          end

          private

          def tag_count
            locations.count
          end

          attr_reader :tag_name
          attr_reader :limit
          attr_reader :locations
        end
      end
    end
  end
end
