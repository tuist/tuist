module SimCtl
  class Command
    module Boot
      # Boots a device
      #
      # @param device [SimCtl::Device] the device to boot
      # @return [void]
      def boot_device(device)
        Executor.execute(command_for('boot', device.udid))
      end
    end
  end
end
