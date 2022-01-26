module Fastlane
  module Helper
    class SimctlHelper
      def self.execute_with_simulator_ready(action, block, runtime, type, name)
        device = create_device(runtime, type, name)
        device.boot
        device.wait(90) do |d|
          Fastlane::UI.message("Waiting for simulator `#{d.name}` to be ready")
          d.state == :booted && d.ready?
        end
        begin
          block.call(action.other_action, device)
        rescue StandardError => error
          throw error
        ensure
          delete_device(device)
        end
      end

      def self.create_device(runtime, type, name)
        runtime = if runtime.eql? 'latest'
                    SimCtl::Runtime.latest('ios')
                  else
                    SimCtl.runtime(name: runtime)
                  end
        device_type = SimCtl.devicetype(name: type)
        device_name = name
        device_name ||= type.to_s.instance_eval do |obj|
          obj += "-#{ENV['JOB_NAME']}" if ENV['JOB_NAME']
          obj += "@#{ENV['BUILD_NUMBER']}" if ENV['BUILD_NUMBER']
          obj
        end
        Fastlane::UI.message("Starting simulator with runtime: `#{runtime.name}`, device type: `#{device_type.name}`"\
          " and device name: `#{device_name}`")
        SimCtl.reset_device(device_name, device_type, runtime)
      end

      def self.delete_device(device)
        if device.state != :shutdown
          device.shutdown
          device.kill
          device.wait do |d|
            Fastlane::UI.message("Waiting for simulator `#{d.name}` to be shutdown")
            d.state == :shutdown
          end
        end
        Fastlane::UI.message("Deleting simulator `#{device.name}`")
        device.delete
      end
    end
  end
end
