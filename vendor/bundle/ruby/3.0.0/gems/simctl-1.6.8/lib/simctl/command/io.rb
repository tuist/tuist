require 'shellwords'

module SimCtl
  class Command
    module IO
      # Saves a screenshot to a file
      #
      # @param device [SimCtl::Device] the device the screenshot should be taken from
      # @param file Path where the screenshot should be saved to
      # @param opts Optional hash that supports two keys:
      # * type: Can be png, tiff, bmp, gif, jpeg (default is png)
      # * display: Can be main or tv for iOS, tv for tvOS and main for watchOS
      # @return [void]
      def screenshot(device, file, opts = {})
        unless Xcode::Version.gte? '8.2'
          raise UnsupportedCommandError, 'Needs at least Xcode 8.2'
        end
        optional_args = opts.map { |k, v| "--#{k}=#{Shellwords.shellescape(v)}" }
        Executor.execute(command_for('io', device.udid, 'screenshot', *optional_args, Shellwords.shellescape(file)))
      end
    end
  end
end
