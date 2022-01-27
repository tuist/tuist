module SimCtl
  class Command
    module Kill
      # Kills a Simulator instance with the given device
      #
      # @param device [SimCtl::Device] the device to kill
      # @return [void]
      def kill_device(device)
        pid = `ps xww | grep Simulator.app | grep -s #{device.udid} | grep -v grep | awk '{print $1}'`.chomp
        if pid.to_i > 0
          system 'kill', pid
        else
          false
        end
      end
    end
  end
end
