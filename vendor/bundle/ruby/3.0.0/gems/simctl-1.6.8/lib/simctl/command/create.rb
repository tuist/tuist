require 'shellwords'

module SimCtl
  class Command
    module Create
      # Creates a device
      #
      # @param name [String] name of the new device
      # @param devicetype [SimCtl::DeviceType] device type of the new device
      # @param runtime [SimCtl::Runtime] runtime of the new device
      # @return [SimCtl::Device] the device that was created
      def create_device(name, devicetype, runtime)
        runtime = runtime(name: runtime) unless runtime.is_a?(Runtime)
        devicetype = devicetype(name: devicetype) unless devicetype.is_a?(DeviceType)
        raise "Invalid runtime: #{runtime}" unless runtime.is_a?(Runtime)
        raise "Invalid devicetype: #{devicetype}" unless devicetype.is_a?(DeviceType)
        command = command_for('create', Shellwords.shellescape(name), devicetype.identifier, runtime.identifier)
        device = Executor.execute(command) do |identifier|
          device(udid: identifier)
        end
        device.wait { |d| d.state == :shutdown && File.exist?(d.path.device_plist) }
        device
      end
    end
  end
end
