# frozen_string_literal: true

module Cucumber
  module Filters
    class TagLimits
      class TestCaseIndex
        def initialize
          @index = Hash.new { |hash, key| hash[key] = [] }
        end

        def add(test_case)
          test_case.tags.map(&:name).each do |tag_name|
            index[tag_name] << test_case
          end
        end

        def count_by_tag_name(tag_name)
          index[tag_name].count
        end

        def locations_of_tag_name(tag_name)
          index[tag_name].map(&:location)
        end

        private

        attr_accessor :index
      end
    end
  end
end
