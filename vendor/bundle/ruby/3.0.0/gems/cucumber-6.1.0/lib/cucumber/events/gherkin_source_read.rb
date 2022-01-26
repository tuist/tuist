require 'cucumber/core/events'

module Cucumber
  module Events
    # Fired after we've read in the contents of a feature file
    class GherkinSourceRead < Core::Event.new(:path, :body)
      # The path to the file
      attr_reader :path

      # The raw Gherkin source
      attr_reader :body
    end
  end
end
