require 'shellwords'

module SimCtl
  class Command
    module Launch
      SUPPORTED_SCALE = [1.0, 0.75, 0.5, 0.25].freeze

      # Launches a Simulator instance with the given device
      #
      # @param device [SimCtl::Device] the device to launch
      # @return [void]
      def launch_device(device, scale = 1.0, opts = {})
        raise "unsupported scale '#{scale}' (supported: #{SUPPORTED_SCALE.join(', ')})" unless SUPPORTED_SCALE.include?(scale)
        # Launching the same device twice does not work.
        # Simulator.app would just hang. Solution: Kill first.
        kill_device(device)
        args = {
          '-ConnectHardwareKeyboard' => 1,
          '-CurrentDeviceUDID' => device.udid,
          "-SimulatorWindowLastScale-#{device.devicetype.identifier}" => scale
        }
        args['-DeviceSetPath'] = Shellwords.shellescape(SimCtl.device_set_path) unless SimCtl.device_set_path.nil?
        args = args.merge(opts).zip.flatten.join(' ')
        command = "open -Fgn #{Xcode::Path.home}/Applications/Simulator.app --args #{args}"
        system command
      end

      # Launches an app in the given device
      #
      # @param device [SimCtl::Device] the device to launch
      # @param opts [Hash] options hash - `{ wait_for_debugger: true/false }`
      # @param identifier [String] the app identifier
      # @param args [Array] optional launch arguments
      # @return [void]
      def launch_app(device, identifier, args = [], opts = {})
        launch_args = args.map { |arg| Shellwords.shellescape arg }
        launch_opts = opts[:wait_for_debugger] ? '-w' : ''
        Executor.execute(command_for('launch', launch_opts, device.udid, identifier, launch_args))
      end
    end
  end
end
