require 'json'
require 'socket'
require 'cucumber/wire/connection'
require 'cucumber/wire/configuration'
require 'cucumber/wire/data_packet'
require 'cucumber/wire/exception'
require 'cucumber/wire/step_definition'
require 'cucumber/wire/snippet'
require 'cucumber/configuration'
require 'cucumber/step_match'

module Cucumber
  module Wire

    class Connections
      attr_reader :connections
      private :connections

      def initialize(connections, configuration, registry)
        raise ArgumentError unless connections
        @connections = connections
        @configuration = configuration
        @registry = registry
      end

      def find_match(test_step)
        matches = step_matches(test_step.name)
        return unless matches.any?
        # TODO: handle ambiguous matches (push to cucumber?)
        matches.first
      end

      def step_matches(step_name)
        connections.map{ |c| c.step_matches(step_name, @registry)}.flatten
      end

      def begin_scenario(test_case)
        connections.each { |c| c.begin_scenario(test_case) }
      end

      def end_scenario(test_case)
        connections.each { |c| c.end_scenario(test_case) }
      end

      def snippets(code_keyword, step_name, multiline_arg_class_name)
        connections.map { |c| c.snippet_text(code_keyword, step_name, multiline_arg_class_name) }.flatten
      end

    end
  end
end
