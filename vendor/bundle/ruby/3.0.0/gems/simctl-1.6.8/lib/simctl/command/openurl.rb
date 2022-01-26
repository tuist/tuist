require 'shellwords'

module SimCtl
  class Command
    module OpenUrl
      # Opens a url
      #
      # @param device [SimCtl::Device] the device that should open the url
      # @param url The url to open on the device
      # @return [void]
      def open_url(device, url)
        Executor.execute(command_for('openurl', device.udid, Shellwords.shellescape(url)))
      end
    end
  end
end
