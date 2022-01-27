# coding: utf-8
require 'cucumber/core/event'

module Cucumber
  module Core
    module Events

      class Envelope < Event.new(:envelope)
        attr_reader :envelope
      end

      # Signals that a gherkin source has been parsed
      class GherkinSourceParsed < Event.new(:gherkin_document)
        # @return [GherkinDocument] the GherkinDocument Ast Node
        attr_reader :gherkin_document

      end

      # Signals that a Test::Step was created from a PickleStep
      class TestStepCreated < Event.new(:test_step, :pickle_step)
        # The created test step
        attr_reader :test_step

        # The source pickle step
        attr_reader :pickle_step
      end

      # Signals that a Test::Case was created from a Pickle
      class TestCaseCreated < Event.new(:test_case, :pickle)
        # The created test step
        attr_reader :test_case

        # The source pickle step
        attr_reader :pickle
      end

      # Signals that a {Test::Case} is about to be executed
      class TestCaseStarted < Event.new(:test_case)

        # @return [Test::Case] the test case to be executed
        attr_reader :test_case

      end

      # Signals that a {Test::Step} is about to be executed
      class TestStepStarted < Event.new(:test_step)

        # @return [Test::Step] the test step to be executed
        attr_reader :test_step

      end

      # Signals that a {Test::Step} has finished executing
      class TestStepFinished < Event.new(:test_step, :result)

        # @return [Test::Step] the test step that was executed
        attr_reader :test_step

        # @return [Test::Result] the result of running the {Test::Step}
        attr_reader :result

      end

      # Signals that a {Test::Case} has finished executing
      class TestCaseFinished < Event.new(:test_case, :result)

        # @return [Test::Case] that was executed
        attr_reader :test_case

        # @return [Test::Result] the result of running the {Test::Step}
        attr_reader :result

      end

      # The registry contains all the events registered in the core,
      # that will be used by the {EventBus} by default.
      def self.registry
        build_registry(
          Envelope,
          GherkinSourceParsed,
          TestStepCreated,
          TestCaseCreated,
          TestCaseStarted,
          TestStepStarted,
          TestStepFinished,
          TestCaseFinished,
        )
      end

      # Build an event registry to be passed to the {EventBus}
      # constructor from a list of types.
      #
      # Each type must respond to `event_id` so that it can be added
      # to the registry hash.
      #
      # @return [Hash{Symbol => Class}]
      def self.build_registry(*types)
        types.map { |type| [type.event_id, type] }.to_h
      end
    end
  end
end
