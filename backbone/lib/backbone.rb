# frozen_string_literal: true

require 'cli/ui'
require 'cli/kit'

CLI::UI::StdoutRouter.enable

module Backbone
  extend CLI::Kit::Autocall

  TOOL_NAME = 'backbone'
  ROOT      = File.expand_path('..', __dir__)
  LOG_FILE  = '/tmp/backbone.log'

  autoload(:EntryPoint, 'backbone/entry_point')
  autoload(:Commands,   'backbone/commands')

  autocall(:Config)  { CLI::Kit::Config.new(tool_name: TOOL_NAME) }
  autocall(:Command) { CLI::Kit::BaseCommand }

  autocall(:Executor) { CLI::Kit::Executor.new(log_file: LOG_FILE) }
  autocall(:Resolver) do
    CLI::Kit::Resolver.new(
      tool_name: TOOL_NAME,
      command_registry: Backbone::Commands::Registry
    )
  end

  autocall(:ErrorHandler) do
    CLI::Kit::ErrorHandler.new(
      log_file: LOG_FILE,
      exception_reporter: nil
    )
  end
end
