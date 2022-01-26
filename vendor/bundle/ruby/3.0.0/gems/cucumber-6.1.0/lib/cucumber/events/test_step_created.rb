# frozen_string_literal: true

require 'cucumber/core/events'

module Cucumber
  module Events
    # Event fired when a TestStep is created from a PickleStep
    class TestStepCreated < Core::Event.new(:test_step, :pickle_step)
      attr_reader :test_step
      attr_reader :pickle_step
    end
  end
end
