require 'cli/kit'

module CLI
  module Kit
    class Resolver
      def initialize(tool_name:, command_registry:)
        @tool_name = tool_name
        @command_registry = command_registry
      end

      def call(args)
        args = args.dup
        command_name = args.shift

        command, resolved_name = @command_registry.lookup_command(command_name)

        if command.nil?
          command_not_found(command_name)
          raise CLI::Kit::AbortSilent # Already output message
        end

        [command, resolved_name, args]
      end

      private

      def command_not_found(name)
        CLI::UI::Frame.open("Command not found", color: :red, timing: false) do
          $stderr.puts(CLI::UI.fmt("{{command:#{@tool_name} #{name}}} was not found"))
        end

        cmds = commands_and_aliases
        if cmds.all? { |cmd| cmd.is_a?(String) }
          possible_matches = cmds.min_by(2) do |cmd|
            CLI::Kit::Levenshtein.distance(cmd, name)
          end

          # We don't want to match against any possible command
          # so reject anything that is too far away
          possible_matches.reject! do |possible_match|
            CLI::Kit::Levenshtein.distance(possible_match, name) > 3
          end

          # If we have any matches left, tell the user
          if possible_matches.any?
            CLI::UI::Frame.open("{{bold:Did you mean?}}", timing: false, color: :blue) do
              possible_matches.each do |possible_match|
                $stderr.puts CLI::UI.fmt("{{command:#{@tool_name} #{possible_match}}}")
              end
            end
          end
        end
      end

      def commands_and_aliases
        @command_registry.command_names + @command_registry.aliases.keys
      end
    end
  end
end
