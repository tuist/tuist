require 'ostruct'

module SimCtl
  class Command
    module StatusBar
      # Clear all status bar overrides
      #
      # @param device [SimCtl::Device] the device
      # @return [void]
      def status_bar_clear(device)
        unless Xcode::Version.gte? '11.4'
          raise UnsupportedCommandError, 'Needs at least Xcode 11.4'
        end
        Executor.execute(command_for('status_bar', device.udid, 'clear'))
      end

      # Set some status bar overrides
      #
      # Refer to `xcrun simctl status_bar` for available options.
      #
      # Example:
      #
      # SimCtl.status_bar_override device, {
      #   time: '9:41',
      #   dataNetwork: 'lte+',
      #   wifiMode: 'active',
      #   cellularMode: 'active',
      #   batteryState: 'charging',
      #   batteryLevel: 50
      # }
      #
      # @param device [SimCtl::Device] the device
      # @param overrides [SimCtl::StatusBarOverrides] or [Hash] the overrides to apply
      # @return [void]
      def status_bar_override(device, overrides)
        unless Xcode::Version.gte? '11.4'
          raise UnsupportedCommandError, 'Needs at least Xcode 11.4'
        end
        overrides = SimCtl::StatusBarOverrides.new overrides unless overrides.is_a?(SimCtl::StatusBarOverrides)
        Executor.execute(command_for('status_bar', device.udid, 'override', *overrides.to_args))
      end
    end
  end
end

module SimCtl
  class StatusBarOverrides < OpenStruct
    def to_args
      to_h.map { |k, v| ["--#{k}", v] }.flatten
    end
  end
end
