module SimCtl
  class Command
    module Uninstall
      # Uninstall an app on a device
      #
      # @param device [SimCtl::Device] the device the app should be uninstalled from
      # @param app_id App identifier of the app that should be uninstalled
      # @return [void]
      def uninstall_app(device, app_id)
        Executor.execute(command_for('uninstall', device.udid, app_id))
      end
    end
  end
end
