module SimCtl
  class Command
    module Shutdown
      # Shutdown a device
      #
      # @param device [SimCtl::Device] the device to shutdown
      # @return [void]
      def shutdown_device(device)
        Executor.execute(command_for('shutdown', device.udid))
      end
    end
  end
end
