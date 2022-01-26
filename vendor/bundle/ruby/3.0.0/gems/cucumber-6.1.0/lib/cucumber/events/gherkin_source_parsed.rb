require 'cucumber/core/events'

module Cucumber
  module Events
    # Fired after we've parsed the contents of a feature file
    class GherkinSourceParsed < Core::Event.new(:gherkin_document)
      # The Gherkin Ast
      attr_reader :gherkin_document
    end
  end
end
