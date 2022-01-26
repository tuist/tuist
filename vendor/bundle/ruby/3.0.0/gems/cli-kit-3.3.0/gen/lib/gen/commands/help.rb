require 'gen'

module Gen
  module Commands
    class Help < Gen::Command
      def call(_args, _name)
        puts CLI::UI.fmt("{{bold:Available commands}}")
        puts ""

        Gen::Commands::Registry.resolved_commands.each do |name, klass|
          puts CLI::UI.fmt("{{command:#{Gen::TOOL_NAME} #{name}}}")
          if klass.respond_to?(:help) && help = klass.help
            puts CLI::UI.fmt(help)
          end
          puts ""
        end
      end
    end
  end
end
