module SimCtl
  class Command
    module Warmup
      # Warms up a device and waits for it to be ready
      #
      # @param devicetype [String] device type string
      # @param runtime [String] runtime string
      # @param timeout [Integer] timeout in seconds to wait until device is ready
      # @return [SimCtl::Device]
      def warmup(devicetype, runtime, timeout = 120)
        devicetype = devicetype(name: devicetype) unless devicetype.is_a?(DeviceType)
        runtime = runtime(name: runtime) unless runtime.is_a?(Runtime)
        device = device(devicetype: devicetype, runtime: runtime)
        raise DeviceNotFound, "Could not find device with type '#{devicetype.name}' and runtime '#{runtime.name}'" if device.nil?
        device.boot if device.state != :booted
        device.wait(timeout) { |d| d.state == :booted && d.ready? }
        device
      end
    end
  end
end
