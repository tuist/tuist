require 'shellwords'

module SimCtl
  class Command
    module Rename
      # Boots a device
      #
      # @param device [SimCtl::Device] the device to boot
      # @param name [String] the new device name
      # @return [void]
      def rename_device(device, name)
        Executor.execute(command_for('rename', device.udid, Shellwords.shellescape(name)))
      end
    end
  end
end
