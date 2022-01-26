module SimCtl
  class StatusBar
    def initialize(device)
      @device = device
    end

    # Clear all status bar overrides
    #
    # @return [void]
    def clear
      SimCtl.status_bar_clear(device)
    end

    # Set some status bar overrides
    #
    # @param overrides [SimCtl::StatusBarOverrides] or [Hash] the overrides to apply
    # @return [void]
    def override(overrides)
      SimCtl.status_bar_override(device, overrides)
    end

    private

    attr_reader :device
  end
end
