#!/usr/bin/env ruby

require 'cli/ui'
require 'cli/kit'

CLI::UI::StdoutRouter.enable

module Example
  extend CLI::Kit::Autocall

  TOOL_NAME = 'example'
  ROOT      = File.expand_path('../..', __FILE__)
  LOG_FILE  = '/tmp/example.log'

  module Commands
    extend CLI::Kit::Autocall

    Registry = CLI::Kit::CommandRegistry.new(
      default: 'hello',
      contextual_resolver: nil
    )

    def self.register(const, cmd, path = nil, &block)
      path ? autoload(const, path) : autocall(const, &block)
      Registry.add(->() { const_get(const) }, cmd)
    end

    # register(:Hello, 'hello', 'a/b/hello')

    register(:Hello, 'hello') do
      Class.new(Example::Command) do
        def call(_args, _name)
          puts "hello, world!"
        end
      end
    end
  end

  autocall(:EntryPoint) do
    Module.new do
      def self.call(args)
        cmd, command_name, args = Example::Resolver.call(args)
        Example::Executor.call(cmd, command_name, args)
      end
    end
  end

  autocall(:Config)  { CLI::Kit::Config.new(tool_name: TOOL_NAME) }
  autocall(:Command) { CLI::Kit::BaseCommand }

  autocall(:Executor) { CLI::Kit::Executor.new(log_file: LOG_FILE) }
  autocall(:Resolver) do
    CLI::Kit::Resolver.new(
      tool_name: TOOL_NAME,
      command_registry: Example::Commands::Registry
    )
  end

  autocall(:ErrorHandler) do
    CLI::Kit::ErrorHandler.new(
      log_file: LOG_FILE,
      exception_reporter: nil
    )
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(Example::ErrorHandler.call do
    Example::EntryPoint.call(ARGV.dup)
  end)
end
