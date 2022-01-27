require 'ostruct'

module SimCtl
  class DeviceLaunchctl
    def initialize(device)
      @device = device
    end

    def list
      fields = %i[pid status name]
      device
        .spawn(device.path.launchctl, ['list'])
        .split("\n")
        .drop(1)
        .map { |item| Hash[fields.zip(item.split("\t"))] }
        .map { |item| OpenStruct.new(item) }
    end

    private

    attr_reader :device
  end
end
