require 'cli/ui'
require 'cli/kit'

CLI::UI::StdoutRouter.enable

module __App__
  extend CLI::Kit::Autocall

  TOOL_NAME = '__app__'
  ROOT      = File.expand_path('../..', __FILE__)
  LOG_FILE  = '/tmp/__app__.log'

  autoload(:EntryPoint, '__app__/entry_point')
  autoload(:Commands,   '__app__/commands')

  autocall(:Config)  { CLI::Kit::Config.new(tool_name: TOOL_NAME) }
  autocall(:Command) { CLI::Kit::BaseCommand }

  autocall(:Executor) { CLI::Kit::Executor.new(log_file: LOG_FILE) }
  autocall(:Resolver) do
    CLI::Kit::Resolver.new(
      tool_name: TOOL_NAME,
      command_registry: __App__::Commands::Registry
    )
  end

  autocall(:ErrorHandler) do
    CLI::Kit::ErrorHandler.new(
      log_file: LOG_FILE,
      exception_reporter: nil
    )
  end
end
