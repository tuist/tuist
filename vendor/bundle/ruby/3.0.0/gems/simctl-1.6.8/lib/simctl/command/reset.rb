module SimCtl
  class Command
    module Reset
      # Kill, shutdown, delete and create a device
      #
      # @param name [String] name of the new device
      # @param device_type [SimCtl::DeviceType] device type of the new device
      # @param runtime [SimCtl::Runtime] runtime of the new device
      # @return [SimCtl::Device] the device that was created
      # @yield [exception] an exception that might happen during shutdown/delete of the old device
      def reset_device(name, device_type, runtime)
        begin
          list_devices.where(name: name, os: runtime.identifier).each do |device|
            device.kill
            device.shutdown if device.state != :shutdown
            device.wait { |d| d.state == :shutdown }
            device.delete
          end
        rescue Exception => exception
          yield exception if block_given?
        end
        device = create_device name, device_type, runtime
        device.wait { |d| d.state == :shutdown }
        device
      end
    end
  end
end
