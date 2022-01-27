require '__app__'

module __App__
  module Commands
    class Example < __App__::Command
      def call(_args, _name)
        puts 'neato'

        if rand < 0.05
          raise(CLI::Kit::Abort, "you got unlucky!")
        end
      end

      def self.help
        "A dummy command.\nUsage: {{command:#{__App__::TOOL_NAME} example}}"
      end
    end
  end
end
