require 'shellwords'

module SimCtl
  class Command
    module Install
      # Installs an app on a device
      #
      # @param device [SimCtl::Device] the device the app should be installed on
      # @param path Absolute path to the app that should be installed
      # @return [void]
      def install_app(device, path)
        Executor.execute(command_for('install', device.udid, Shellwords.shellescape(path)))
      end
    end
  end
end
