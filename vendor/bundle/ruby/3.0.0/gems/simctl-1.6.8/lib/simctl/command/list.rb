module SimCtl
  class Command
    module List
      # Find a device
      #
      # @param filter [Hash] the filter
      # @return [SimCtl::Device, nil] the device matching the given filter
      def device(filter)
        list_devices.where(filter).first
      end

      # Find a device type
      #
      # @param filter [Hash] the filter
      # @return [SimCtl::DeviceType] the device type matching the given filter
      # @raise [DeviceTypeNotFound] if the device type could not be found
      def devicetype(filter)
        device_type = list_devicetypes.where(filter).first
        device_type || raise(DeviceTypeNotFound, "Could not find a device type matching #{filter.inspect}")
      end

      # List all devices
      #
      # @return [SimCtl::List] a list of SimCtl::Device objects
      def list_devices
        Executor.execute(command_for('list', '-j', 'devices')) do |json|
          devices = json['devices'].map { |os, devs| devs.map { |device| Device.new(device.merge(os: os)) } }
          SimCtl::List.new(devices.flatten)
        end
      end

      # List all device types
      #
      # @return [SimCtl::List] a list of SimCtl::DeviceType objects
      def list_devicetypes
        Executor.execute(command_for('list', '-j', 'devicetypes')) do |json|
          SimCtl::List.new(json['devicetypes'].map { |devicetype| DeviceType.new(devicetype) })
        end
      end

      # List all runtimes
      #
      # @return [SimCtl::List] a list of SimCtl::Runtime objects
      def list_runtimes
        Executor.execute(command_for('list', '-j', 'runtimes')) do |json|
          SimCtl::List.new(json['runtimes'].map { |runtime| Runtime.new(runtime) })
        end
      end

      # Find a runtime
      #
      # @param filter [Hash] the filter
      # @return [SimCtl::Runtime] the runtime matching the given filter
      # @raise [RuntimeNotFound] if the runtime could not be found
      def runtime(filter)
        runtime = list_runtimes.where(filter).first
        runtime || raise(RuntimeNotFound, "Could not find a runtime matching #{filter.inspect}")
      end
    end
  end
end
