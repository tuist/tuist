require 'simctl/command'
require 'simctl/device'
require 'simctl/device_type'
require 'simctl/list'
require 'simctl/runtime'
require 'simctl/xcode/path'
require 'simctl/xcode/version'

module SimCtl
  class UnsupportedCommandError < StandardError; end
  class DeviceTypeNotFound < StandardError; end
  class RuntimeNotFound < StandardError; end
  class DeviceNotFound < StandardError; end

  @@default_timeout = 15

  class << self
    def default_timeout
      @@default_timeout
    end

    def default_timeout=(timeout)
      @@default_timeout = timeout
    end

    def command
      return @command if defined?(@command)
      @command = SimCtl::Command.new
    end

    private

    def respond_to_missing?(method_name, include_private = false)
      command.respond_to?(method_name, include_private)
    end

    def method_missing(method_name, *args, &block)
      if command.respond_to?(method_name)
        return command.send(method_name, *args, &block)
      end
      super
    end
  end
end
