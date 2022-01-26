require 'cucumber/wire/connections'
require 'cucumber/wire/add_hooks_filter'
require 'cucumber/step_match_search'

module Cucumber
  module Wire
    class Plugin
      attr_reader :config, :registry
      private :config, :registry

      def initialize(config, registry)
        @config = config
        @registry = registry
      end

      def install
        connections = Connections.new(wire_files.map { |f| create_connection(f) }, config, registry)
        config.filters << Filters::ActivateSteps.new(StepMatchSearch.new(connections.method(:step_matches), @config), @config)
        config.filters << AddHooksFilter.new(connections) unless @config.dry_run?
        config.register_snippet_generator Snippet::Generator.new(connections)
      end

      def create_connection(wire_file)
        Connection.new(Configuration.from_file(wire_file))
      end

      def wire_files
        # TODO: change Cucumber's config object to allow us to get this information
        config.send(:require_dirs).map { |dir| Dir.glob("#{dir}/**/*.wire") }.flatten
      end
    end
  end
end
