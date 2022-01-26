require 'securerandom'
require 'spec_helper'

RSpec.describe SimCtl, order: :defined do
  before(:all) do
    @name = SecureRandom.hex
    @devicetype = SimCtl.devicetype(name: 'iPhone 8')
    @runtime = SimCtl::Runtime.latest(:ios)
    @device = SimCtl.create_device @name, @devicetype, @runtime
    @device.wait { |d| d.state == :shutdown }
  end

  after(:all) do
    with_rescue { @device.kill }
    with_rescue { @device.wait { |d| d.state == :shutdown } }
    with_rescue { @device.delete }
  end

  describe 'creating a device' do
    it 'raises exception if devicetype lookup failed' do
      expect { SimCtl.create_device @name, 'invalid devicetype', @runtime }.to raise_error SimCtl::DeviceTypeNotFound
    end

    it 'raises exception if runtime lookup failed' do
      expect { SimCtl.create_device @name, @devicetype, 'invalid runtime' }.to raise_error SimCtl::RuntimeNotFound
    end
  end

  describe 'device properties' do
    it 'is a device' do
      expect(@device).to be_kind_of SimCtl::Device
    end

    it 'has a name property' do
      expect(@device.name).to be == @name
    end

    it 'has a devicetype property' do
      expect(@device.devicetype).to be == @devicetype
    end

    it 'has a runtime property' do
      expect(@device.runtime).to be == @runtime
    end

    it 'has a availability property' do
      expect(@device.is_available).not_to be_nil
    end

    it 'has a os property' do
      expect(@device.os).not_to be_nil
    end

    it 'state is shutdown' do
      expect(@device.state).to be == :shutdown
    end

    describe '#path' do
      before(:all) do
        @device.boot
        @device.wait { |d| File.exist?(d.path.device_plist) && File.exist?(d.path.global_preferences_plist) }
      end

      after(:all) do
        @device.shutdown
        @device.wait { |d| d.state == :shutdown }
      end

      it 'has a device plist' do
        expect(File).to exist(@device.path.device_plist)
      end

      it 'has a global preferences plist' do
        expect(File).to exist(@device.path.global_preferences_plist)
      end

      it 'has a home' do
        expect(File).to exist(@device.path.home)
      end

      it 'has a launchctl' do
        expect(File).to exist(@device.path.launchctl)
      end
    end
  end

  describe 'device settings' do
    describe 'update hardware keyboard' do
      it 'creates the preferences plist' do
        File.delete(@device.path.preferences_plist) if File.exist?(@device.path.preferences_plist)
        @device.settings.update_hardware_keyboard(false)
        expect(File).to exist(@device.path.preferences_plist)
      end
    end

    describe 'disable keyboard helpers' do
      it 'creates the preferences plist' do
        File.delete(@device.path.preferences_plist) if File.exist?(@device.path.preferences_plist)
        @device.settings.disable_keyboard_helpers
        expect(File).to exist(@device.path.preferences_plist)
      end
    end

    describe 'setting the device language' do
      it 'sets the device language' do
        @device.settings.set_language('de')
        content = plist(@device.path.global_preferences_plist)
        expect(content['AppleLanguages']).to include('de')
      end
    end

    describe 'setting the device locale' do
      it 'sets the device locale' do
        @device.settings.set_locale('en_DE')
        content = plist(@device.path.global_preferences_plist)
        expect(content['AppleLocale']).to be == 'en_DE'
      end
    end
  end

  describe 'finding the device' do
    it 'finds the device by udid' do
      expect(SimCtl.device(udid: @device.udid)).to be == @device
    end

    it 'finds the device by name' do
      expect(SimCtl.device(name: @device.name)).to be == @device
    end

    unless SimCtl.device_set_path.nil?
      it 'finds the device by runtime' do
        expect(SimCtl.device(runtime: @device.runtime)).to be == @device
      end

      it 'finds the device by devicetype' do
        expect(SimCtl.device(devicetype: @device.devicetype)).to be == @device
      end

      it 'finds the device by all given properties' do
        expect(SimCtl.device(udid: @device.udid, name: @device.name, runtime: @device.runtime, devicetype: @device.devicetype)).to be == @device
      end
    end
  end

  describe 'renaming the device' do
    it 'renames the device' do
      @device.rename('new name')
      expect(@device.name).to be == 'new name'
      expect(SimCtl.device(udid: @device.udid).name).to be == 'new name'
    end
  end

  describe 'erasing the device' do
    it 'erases the device' do
      @device.erase
    end
  end

  describe 'launching the device' do
    it 'launches the device' do
      @device.boot
      @device.wait { |d| d.state == :booted }
      expect(@device.state).to be == :booted
    end

    it 'is ready' do
      @device.wait(&:ready?)
      expect(@device).to be_ready
    end
  end

  describe 'overriding status bar values' do
    if SimCtl::Xcode::Version.gte?('11.4')
      it 'overrides the status bar values' do
        @device.status_bar.override SimCtl::StatusBarOverrides.new(
          time: '10:45',
          dataNetwork: 'lte+',
          wifiMode: 'active',
          cellularMode: 'active',
          batteryState: 'charging',
          batteryLevel: 50
        )
      end

      it 'overrides the status bar values with a hash' do
        @device.status_bar.override(
          time: '10:45',
          dataNetwork: 'lte+',
          wifiMode: 'active',
          cellularMode: 'active',
          batteryState: 'charging',
          batteryLevel: 50
        )
      end

      it 'clears the status bar' do
        @device.status_bar.clear
      end
    else
      it 'raises exception' do
        expect { @device.status_bar.clear }.to raise_error SimCtl::UnsupportedCommandError
        expect { @device.status_bar.override(time: '10:45') }.to raise_error SimCtl::UnsupportedCommandError
      end
    end
  end

  describe 'launching a system app' do
    it 'launches Safari' do
      @device.launch_app('com.apple.mobilesafari')
    end
  end

  describe 'taking a screenshot' do
    if SimCtl::Xcode::Version.gte? '8.2'
      it 'takes a screenshot' do
        file = File.join(Dir.mktmpdir, 'screenshot.png')
        @device.screenshot(file)
        expect(File).to exist(file)
      end
    else
      it 'raises exception' do
        expect { @device.screenshot('/tmp/foo.png') }.to raise_error SimCtl::UnsupportedCommandError
      end
    end
  end

  describe 'spawning a process' do
    it 'spawns launchctl list' do
      output = @device.spawn(@device.path.launchctl, ['list'])
      expect(output.length).to be > 0
    end
  end

  describe 'installing an app' do
    before(:all) do
      system 'cd spec/SampleApp && xcodebuild -sdk iphonesimulator >/dev/null 2>&1'
    end

    it 'installs SampleApp' do
      @device.install('spec/SampleApp/build/Release-iphonesimulator/SampleApp.app')
    end
  end

  describe 'launching an app' do
    it 'launches SampleApp' do
      @device.launch_app('com.github.plu.simctl.SampleApp')
    end
  end

  describe 'terminating an app' do
    if SimCtl::Xcode::Version.gte? '8.2'
      it 'terminates SampleApp' do
        @device.terminate_app('com.github.plu.simctl.SampleApp')
      end
    else
      it 'raises exception' do
        expect { @device.terminate_app('com.github.plu.simctl.SampleApp') }.to raise_error SimCtl::UnsupportedCommandError
      end
    end
  end

  describe 'changing privacy settings' do
    if SimCtl::Xcode::Version.gte?('11.4')
      it 'resets all privacy settings' do
        @device.privacy('reset', 'all', 'com.github.plu.simctl.SampleApp')
      end
    else
      it 'raises exception' do
        expect { @device.privacy('reset', 'all', 'com.github.plu.simctl.SampleApp') }.to raise_error SimCtl::UnsupportedCommandError
      end
    end
  end

  describe 'uninstall an app' do
    it 'uninstalls SampleApp' do
      @device.uninstall('com.github.plu.simctl.SampleApp')
    end
  end

  describe 'opening a url' do
    it 'opens some url' do
      @device.open_url('https://www.github.com')
    end
  end

  describe 'shutdown the device' do
    it 'state is booted' do
      expect(@device.state).to be == :booted
    end

    it 'shuts down the device' do
      @device.shutdown
      @device.wait { |d| d.state == :shutdown }
    end

    it 'state is shutdown' do
      expect(@device.state).to be == :shutdown
    end
  end

  describe 'booting the device' do
    it 'state is shutdown' do
      expect(@device.state).to be == :shutdown
    end

    it 'boots the device' do
      @device.boot
      @device.wait { |d| d.state == :booted }
      expect(@device.state).to be == :booted
    end

    it 'state is booted' do
      expect(@device.state).to be == :booted
    end

    it 'is ready' do
      @device.wait(&:ready?)
      expect(@device).to be_ready
    end
  end

  describe 'shutting down the device' do
    it 'state is booted' do
      expect(@device.state).to be == :booted
    end

    it 'shuts down the device' do
      @device.shutdown
      @device.wait { |d| d.state == :shutdown }
    end

    it 'state is shutdown' do
      expect(@device.state).to be == :shutdown
    end
  end

  describe 'resetting the device' do
    it 'deletes the old device and creates a new one' do
      new_device = @device.reset
      expect(new_device.name).to be == @device.name
      expect(new_device.devicetype).to be == @device.devicetype
      expect(new_device.runtime).to be == @device.runtime
      expect(new_device.udid).not_to be == @device.udid
      expect(SimCtl.device(udid: @device.udid)).to be_nil
      @device = new_device
    end
  end

  describe 'deleting the device' do
    it 'deletes the device' do
      device = SimCtl.create_device @name, @devicetype, @runtime
      device.delete
      device.wait { SimCtl.device(udid: device.udid).nil? }
      expect(SimCtl.device(udid: device.udid)).to be_nil
    end
  end
end
