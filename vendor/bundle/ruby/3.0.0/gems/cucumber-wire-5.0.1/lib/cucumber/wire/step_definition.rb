require 'cucumber/core/test/location'

module Cucumber
  module Wire
    class StepDefinition
      attr_reader :regexp_source, :location, :registry, :expression

      def initialize(connection, data, registry)
        @connection = connection
        @registry   = registry
        @id              = data['id']
        @regexp_source   = Regexp.new(data['regexp']) rescue data['regexp'] || "Unknown"
        @expression      = registry.create_expression(@regexp_source)
        @location        = Core::Test::Location.from_file_colon_line(data['source'] || "unknown:0")
      end

      def invoke(args)
        @connection.invoke(@id, args)
      end

    end
  end
end
