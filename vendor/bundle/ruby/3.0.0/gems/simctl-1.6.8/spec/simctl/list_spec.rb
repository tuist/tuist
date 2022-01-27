require 'spec_helper'

RSpec.describe SimCtl do
  describe '#devicetype' do
    it 'find device type by name' do
      expect(SimCtl.devicetype(name: 'iPhone 6')).to be_kind_of SimCtl::DeviceType
    end

    it 'raise exception if device type is not found' do
      expect { SimCtl.devicetype(name: 'iPhone 1') }.to raise_error SimCtl::DeviceTypeNotFound
    end
  end

  describe '#list_devicetypes' do
    it 'contains some devicetypes' do
      expect(SimCtl.list_devicetypes.count).to be > 0
    end

    it 'is a SimCtl::DeviceType object' do
      expect(SimCtl.list_devicetypes.first).to be_kind_of SimCtl::DeviceType
    end

    it 'parses identifier property' do
      expect(SimCtl.list_devicetypes.first.identifier).not_to be_nil
    end

    it 'parses name property' do
      expect(SimCtl.list_devicetypes.first.name).not_to be_nil
    end
  end

  describe '#list_runtimes' do
    it 'contains some runtimes' do
      expect(SimCtl.list_runtimes.count).to be > 0
    end

    it 'is a SimCtl::Runtime object' do
      expect(SimCtl.list_runtimes.first).to be_kind_of SimCtl::Runtime
    end

    it 'parses availability property' do
      expect(SimCtl.list_runtimes.first.is_available).not_to be_nil
    end

    it 'parses buildversion property' do
      expect(SimCtl.list_runtimes.first.buildversion).not_to be_nil
    end

    it 'parses identifier property' do
      expect(SimCtl.list_runtimes.first.identifier).not_to be_nil
    end

    it 'parses name property' do
      expect(SimCtl.list_runtimes.first.name).not_to be_nil
    end

    it 'return latest ios runtime' do
      expect(SimCtl::Runtime.latest(:ios)).to be_kind_of SimCtl::Runtime
    end

    it 'return latest tvos runtime' do
      expect(SimCtl::Runtime.latest(:tvos)).to be_kind_of SimCtl::Runtime
    end

    it 'return latest watchos runtime' do
      expect(SimCtl::Runtime.latest(:watchos)).to be_kind_of SimCtl::Runtime
    end
  end

  describe '#runtime' do
    it 'find runtime by name' do
      expect(SimCtl.runtime(name: 'iOS 12.1')).to be_kind_of SimCtl::Runtime
    end

    it 'raise exception if runtime is not found' do
      expect { SimCtl.runtime(name: 'iOS 17.0') }.to raise_error SimCtl::RuntimeNotFound
    end

    it 'finds the latest runtime' do
      if SimCtl::Xcode::Version.gte?('11.4')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '13.4'
      elsif SimCtl::Xcode::Version.gte?('11.3')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '13.3'
      elsif SimCtl::Xcode::Version.gte?('11.2')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '13.2.2'
      elsif SimCtl::Xcode::Version.gte?('10.3')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '12.4'
      elsif SimCtl::Xcode::Version.gte?('9.0')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '11.0'
      elsif SimCtl::Xcode::Version.gte?('8.3')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '10.3.1'
      elsif SimCtl::Xcode::Version.gte?('8.2')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '10.2'
      elsif SimCtl::Xcode::Version.gte?('8.1')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '10.1'
      elsif SimCtl::Xcode::Version.gte?('8.0')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '10.0'
      elsif SimCtl::Xcode::Version.gte?('7.3')
        expect(SimCtl::Runtime.latest(:ios).version).to be == '9.3'
      end
    end
  end

  describe 'unknown method' do
    it 'raise an exception' do
      expect { SimCtl.foo }.to raise_error NoMethodError
    end
  end
end
