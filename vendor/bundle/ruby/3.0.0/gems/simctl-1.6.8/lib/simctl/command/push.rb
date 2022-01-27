require 'fileutils'
require 'json'
require 'tempfile'

module SimCtl
  class Command
    module Push
      # Send some push notification
      #
      # @param device [SimCtl::Device] the device
      # @param bundle [String] bundle identifier
      # @param payload the JSON payload. This can be a JSON [String], some [Hash] or
      #                just a [String] path to a local file containing a JSON payload
      # @return [void]
      def push(device, bundle, payload)
        unless Xcode::Version.gte? '11.4'
          raise UnsupportedCommandError, 'Needs at least Xcode 11.4'
        end

        file = Tempfile.new('push')

        if payload.is_a?(Hash)
          JSON.dump payload, file
          file.close
        elsif payload.is_a?(String) && File.exist?(payload)
          file.close
          FileUtils.cp payload, file.path
        else
          file.write payload
          file.close
        end

        Executor.execute(command_for('push', device.udid, bundle, file.path))
      end
    end
  end
end
