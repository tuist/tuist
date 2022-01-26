require 'json'
require 'open3'

module SimCtl
  class Executor
    class << self
      def execute(command)
        command = command.flatten.join(' ')
        $stderr.puts command if ENV['SIMCTL_DEBUG']
        Open3.popen3(command) do |_stdin, stdout, stderr, result|
          output = stdout.read
          if result.value.to_i > 0
            output = stderr.read if output.empty?
            raise output
          end
          return unless block_given?
          if looks_like_json?(output)
            yield JSON.parse(output)
          else
            yield output.chomp
          end
        end
      end

      private

      def looks_like_json?(output)
        output.start_with?('[', '{')
      end
    end
  end
end
