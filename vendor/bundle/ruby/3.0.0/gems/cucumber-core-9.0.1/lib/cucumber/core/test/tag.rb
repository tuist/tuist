# frozen_string_literal: true
module Cucumber
  module Core
    module Test
      class Tag
        include HasLocation

        attr_reader :name

        def initialize(location, name)
          @location = location
          @name = name
        end

        def inspect
          %{#<#{self.class} "#{name}" (#{location})>}
        end
      end
    end
  end
end
