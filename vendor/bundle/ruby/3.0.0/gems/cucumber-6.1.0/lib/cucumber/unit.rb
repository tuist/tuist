# frozen_string_literal: true

module Cucumber
  class Unit
    def initialize(step_collection)
      @step_collection = step_collection
    end

    def step_count
      @step_collection.length
    end
  end
end
