require 'cfpropertylist'
require 'ostruct'
require 'simctl/device_launchctl'
require 'simctl/device_path'
require 'simctl/device_settings'
require 'simctl/object'
require 'simctl/status_bar'
require 'timeout'

module SimCtl
  class Device < Object
    extend Gem::Deprecate

    attr_reader :is_available, :name, :os, :state, :udid

    def initialize(args)
      args['is_available'] = args.delete('isAvailable')
      super
    end

    def availability
      is_available
    end
    deprecate :availability, :is_available, 2020, 8

    # Returns true/false if the device is available
    #
    # @return [Bool]
    def available?
      is_available !~ /unavailable/i
    end

    # Boots the device
    #
    # @return [void]
    def boot
      SimCtl.boot_device(self)
    end

    # Deletes the device
    #
    # @return [void]
    def delete
      SimCtl.delete_device(self)
    end

    # Returns the device type
    #
    # @return [SimCtl::DeviceType]
    def devicetype
      @devicetype ||= SimCtl.devicetype(identifier: plist.deviceType)
    end

    # Erases the device
    #
    # @return [void]
    def erase
      SimCtl.erase_device(self)
    end

    # Installs an app on a device
    #
    # @param path Absolute path to the app that should be installed
    # @return [void]
    def install(path)
      SimCtl.install_app(self, path)
    end

    # Uninstall an app from a device
    #
    # @param app_id App identifier of the app that should be uninstalled
    # @return [void]
    def uninstall(app_id)
      SimCtl.uninstall_app(self, app_id)
    end

    # Kills the device
    #
    # @return [void]
    def kill
      SimCtl.kill_device(self)
    end

    # Launches the Simulator
    #
    # @return [void]
    def launch(scale = 1.0, opts = {})
      SimCtl.launch_device(self, scale, opts)
    end

    # Returns the launchctl object
    #
    # @ return [SimCtl::DeviceLaunchctl]
    def launchctl
      @launchctl ||= DeviceLaunchctl.new(self)
    end

    # Launches an app in the given device
    #
    # @param opts [Hash] options hash - `{ wait_for_debugger: true/false }`
    # @param identifier [String] the app identifier
    # @param args [Array] optional launch arguments
    # @return [void]
    def launch_app(identifier, args = [], opts = {})
      SimCtl.launch_app(self, identifier, args, opts)
    end

    # Terminates an app on the given device
    #
    # @param identifier [String] the app identifier
    # @param args [Array] optional terminate arguments
    # @return [void]
    def terminate_app(identifier, args = [])
      SimCtl.terminate_app(self, identifier, args)
    end

    # Opens the url on the device
    #
    # @param url [String] The url to be opened on the device
    # @return [void]
    def open_url(url)
      SimCtl.open_url(self, url)
    end

    def path
      @path ||= DevicePath.new(self)
    end

    # Change privacy settings
    #
    # @param action [String] grant, revoke, reset
    # @param service [String] all, calendar, contacts-limited, contacts, location,
    #                location-always, photos-add, photos, media-library, microphone,
    #                motion, reminders, siri
    # @param bundle [String] bundle identifier
    # @return [void]
    def privacy(action, service, bundle)
      SimCtl.privacy(self, action, service, bundle)
    end

    # Returns true/false if the device is ready
    # Uses [SimCtl::DeviceLaunchctl] to look for certain services being running.
    #
    # Unfortunately the 'booted' state does not mean the Simulator is ready for
    # installing or launching applications.
    #
    # @return [Bool]
    def ready?
      running_services = launchctl.list.reject { |service| service.pid.to_i == 0 }.map(&:name)
      (required_services_for_ready - running_services).empty?
    end

    # Reloads the device information
    #
    # @return [void]
    def reload
      device = SimCtl.device(udid: udid)
      device.instance_variables.each do |ivar|
        instance_variable_set(ivar, device.instance_variable_get(ivar))
      end
    end

    # Renames the device
    #
    # @return [void]
    def rename(name)
      SimCtl.rename_device(self, name)
      @name = name
    end

    # Resets the device
    #
    # @return [void]
    def reset
      SimCtl.reset_device name, devicetype, runtime
    end

    # Returns the runtime object
    #
    # @return [SimCtl::Runtime]
    def runtime
      @runtime ||= SimCtl.runtime(identifier: plist.runtime)
    end

    # Saves a screenshot to a file
    #
    # @param file Path where the screenshot should be saved to
    # @param opts Optional hash that supports two keys:
    # * type: Can be png, tiff, bmp, gif, jpeg (default is png)
    # * display: Can be main or tv for iOS, tv for tvOS and main for watchOS
    # @return [void]
    def screenshot(file, opts = {})
      SimCtl.screenshot(self, file, opts)
    end

    # Returns the settings object
    #
    # @ return [SimCtl::DeviceSettings]
    def settings
      @settings ||= DeviceSettings.new(path)
    end

    # Shuts down the runtime
    #
    # @return [void]
    def shutdown
      SimCtl.shutdown_device(self)
    end

    # Spawn a process on a device
    #
    # @param path [String] path to executable
    # @param args [Array] arguments for the executable
    # @return [void]
    def spawn(path, args = [], opts = {})
      SimCtl.spawn(self, path, args, opts)
    end

    # Returns the state of the device
    #
    # @return [sym]
    def state
      @state.downcase.to_sym
    end

    # Returns the status bar object
    #
    # @return [SimCtl::StatusBar]
    def status_bar
      @status_bar ||= SimCtl::StatusBar.new(self)
    end

    # Reloads the device until the given block returns true
    #
    # @return [void]
    def wait(timeout = SimCtl.default_timeout)
      Timeout.timeout(timeout) do
        loop do
          break if yield SimCtl.device(udid: udid)
        end
      end
      reload
    end

    def ==(other)
      return false if other.nil?
      return false unless other.is_a? Device
      other.udid == udid
    end

    def method_missing(method_name, *args, &block)
      if method_name[-1] == '!'
        new_method_name = method_name.to_s.chop.to_sym
        if respond_to?(new_method_name)
          warn "[#{Kernel.caller.first}] `#{method_name}` is deprecated. Please use `#{new_method_name}` instead."
          return send(new_method_name, &block)
        end
      end
      super
    end

    private

    def plist
      @plist ||= OpenStruct.new(CFPropertyList.native_types(CFPropertyList::List.new(file: path.device_plist).value))
    end

    def required_services_for_ready
      case runtime.type
      when :tvos, :watchos
        if Xcode::Version.gte? '8.0'
          [
            'com.apple.mobileassetd',
            'com.apple.nsurlsessiond'
          ]
        else
          [
            'com.apple.mobileassetd',
            'com.apple.networkd'
          ]
        end
      when :ios
        if Xcode::Version.gte? '9.0'
          [
            'com.apple.backboardd',
            'com.apple.mobile.installd',
            'com.apple.CoreSimulator.bridge',
            'com.apple.SpringBoard'
          ]
        elsif Xcode::Version.gte? '8.0'
          [
            'com.apple.SimulatorBridge',
            'com.apple.SpringBoard',
            'com.apple.backboardd',
            'com.apple.mobile.installd'
          ]
        else
          [
            'com.apple.SimulatorBridge',
            'com.apple.SpringBoard',
            'com.apple.mobile.installd'
          ]
        end
      else
        []
      end
    end
  end
end
