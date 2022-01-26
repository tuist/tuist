require 'cfpropertylist'

module SimCtl
  class DevicePath
    def initialize(device)
      @device = device
    end

    def device_plist
      @device_plist ||= File.join(home, 'device.plist')
    end

    def global_preferences_plist
      @global_preferences_plist ||= File.join(home, 'data/Library/Preferences/.GlobalPreferences.plist')
    end

    def home
      @home ||= File.join(device_set_path, device.udid)
    end

    def launchctl
      @launchctl ||= File.join(runtime_root, 'bin/launchctl')
    end

    def preferences_plist
      @preferences_plist ||= File.join(home, 'data/Library/Preferences/com.apple.Preferences.plist')
    end

    private

    attr_reader :device

    def device_set_path
      return SimCtl.device_set_path unless SimCtl.device_set_path.nil?
      File.join(ENV['HOME'], 'Library/Developer/CoreSimulator/Devices')
    end

    def locate_runtime_root
      runtime_identifier = device.runtime.identifier

      [
        Xcode::Path.runtime_profiles,
        '/Library/Developer/CoreSimulator/Profiles/Runtimes/'
      ].each do |parent_dir|
        Dir.glob(File.join(File.expand_path(parent_dir), '*')).each do |dir|
          plist_path = File.join(dir, 'Contents/Info.plist')
          next unless File.exist?(plist_path)
          info = CFPropertyList.native_types(CFPropertyList::List.new(file: plist_path).value)
          next unless info.is_a?(Hash) && (info['CFBundleIdentifier'] == runtime_identifier)
          root_path = File.join(dir, 'Contents/Resources/RuntimeRoot')
          return root_path if File.exist?(root_path)
        end
      end

      Xcode::Path.sdk_root
    end

    def runtime_root
      @runtime_root ||= locate_runtime_root
    end
  end
end
