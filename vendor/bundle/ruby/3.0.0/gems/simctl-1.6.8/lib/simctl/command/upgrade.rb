module SimCtl
  class Command
    module Upgrade
      # Upgrade a device to a newer runtime
      #
      # @param device [SimCtl::Device] the device the upgrade should be performed for
      # @param runtime [SimCtl::Runtime] the runtime the device should be upgrade to
      # @return [void]
      def upgrade(device, runtime)
        Executor.execute(command_for('upgrade', device.udid, runtime.identifier))
      end
    end
  end
end
