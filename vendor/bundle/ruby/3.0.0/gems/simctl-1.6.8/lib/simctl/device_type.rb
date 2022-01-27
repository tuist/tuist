require 'simctl/object'

module SimCtl
  class DeviceType < Object
    attr_reader :identifier, :name

    def ==(other)
      return false if other.nil?
      return false unless other.is_a? DeviceType
      other.identifier == identifier
    end
  end
end
