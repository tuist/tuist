require 'cli/ui'
require 'cli/kit'

CLI::UI::StdoutRouter.enable

module Gen
  extend CLI::Kit::Autocall

  TOOL_NAME = 'cli-kit'
  ROOT      = File.expand_path('../../..', __FILE__)

  TOOL_CONFIG_PATH = File.expand_path(File.join('~', '.config', TOOL_NAME))
  LOG_FILE = File.join(TOOL_CONFIG_PATH, 'logs', 'log.log')
  DEBUG_LOG_FILE = File.join(TOOL_CONFIG_PATH, 'logs', 'debug.log')

  autoload(:Generator, 'gen/generator')

  autoload(:EntryPoint, 'gen/entry_point')
  autoload(:Commands,   'gen/commands')

  autocall(:Config)  { CLI::Kit::Config.new(tool_name: TOOL_NAME) }
  autocall(:Command) { CLI::Kit::BaseCommand }
  autocall(:Logger)  { CLI::Kit::Logger.new(debug_log_file: DEBUG_LOG_FILE) }

  autocall(:Executor) { CLI::Kit::Executor.new(log_file: LOG_FILE) }
  autocall(:Resolver) do
    CLI::Kit::Resolver.new(
      tool_name: TOOL_NAME,
      command_registry: Gen::Commands::Registry
    )
  end

  autocall(:ErrorHandler) do
    CLI::Kit::ErrorHandler.new(
      log_file: LOG_FILE,
      exception_reporter: nil
    )
  end
end
