require 'shellwords'

module SimCtl
  class Command
    module Spawn
      # Spawn a process on a device
      #
      # @param device [SimCtl::Device] the device to spawn a process on
      # @param path [String] path to executable
      # @param args [Array] arguments for the executable
      # @return [String] standard output the spawned process generated
      def spawn(device, path, args = [], _opts = {})
        escaped_path = Shellwords.shellescape(path)
        command = command_for('spawn', device.udid, escaped_path, *args.map { |a| Shellwords.shellwords(a) })
        Executor.execute(command) do |output|
          output
        end
      end
    end
  end
end
