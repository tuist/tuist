module SimCtl
  class Command
    module Delete
      # Delete a device
      #
      # @param device [SimCtl::Device] the device to delete
      # @return [void]
      def delete_device(device)
        Executor.execute(command_for('delete', device.udid))
      end

      # Delete all devices
      #
      # @return [SimCtl::List] a list of all deleted SimCtl::Device objects
      def delete_all_devices
        list_devices.each do |device|
          device.kill
          device.shutdown if device.state != :shutdown
          device.wait { |d| d.state == :shutdown }
          device.delete
        end
      end
    end
  end
end
