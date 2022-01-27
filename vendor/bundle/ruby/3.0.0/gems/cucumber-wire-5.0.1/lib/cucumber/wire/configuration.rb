require 'yaml'
require 'erb'

module Cucumber
  module Wire
    class Configuration
      attr_reader :host, :port, :unix

      def self.from_file(wire_file)
        settings = YAML.load(ERB.new(File.read(wire_file)).result)
        new(settings)
      end

      def initialize(args)
        @host = args['host']
        @port = args['port']
        @unix = args['unix'] if RUBY_PLATFORM !~ /mingw|mswin/
        @timeouts = DEFAULT_TIMEOUTS.merge(args['timeout'] || {})
      end

      def timeout(message = nil)
        return @timeouts[message.to_s] || 3
      end

      def to_s
        return @unix if @unix
        "#{@host}:#{@port}"
      end

      DEFAULT_TIMEOUTS = {
        'connect' => 11,
        'invoke' => 120,
        'begin_scenario' => 120,
        'end_scenario' => 120
      }
    end
  end
end
