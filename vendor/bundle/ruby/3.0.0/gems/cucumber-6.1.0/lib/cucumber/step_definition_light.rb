# frozen_string_literal: true

module Cucumber
  # TODO: pointless, ancient, kill with fire.
  # Only used for keeping track of available and invoked step definitions
  # in a way that also works for other programming languages (i.e. cuke4duke)
  # Used for reporting purposes only (usage formatter).
  class StepDefinitionLight
    attr_reader :regexp_source, :location

    def initialize(regexp_source, location)
      @regexp_source = regexp_source
      @location = location
    end

    def eql?(other)
      regexp_source == other.regexp_source && location == other.location
    end

    def hash
      regexp_source.hash + 31 * location.to_s.hash
    end
  end
end
