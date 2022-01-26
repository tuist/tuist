module SimCtl
  class Command
    module Erase
      # Erase a device
      #
      # @param device [SimCtl::Device] the device to erase
      # @return [void]
      def erase_device(device)
        Executor.execute(command_for('erase', device.udid))
      end
    end
  end
end
