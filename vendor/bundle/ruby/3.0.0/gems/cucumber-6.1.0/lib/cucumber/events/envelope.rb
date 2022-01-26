require 'cucumber/core/events'

module Cucumber
  module Events
    class Envelope < Core::Event.new(:envelope)
      attr_reader :envelope
    end
  end
end
