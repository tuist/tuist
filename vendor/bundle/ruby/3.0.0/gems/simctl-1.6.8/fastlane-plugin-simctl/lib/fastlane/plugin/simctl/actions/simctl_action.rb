require 'simctl'

module Fastlane
  module Actions
    class SimctlAction < Action
      def self.run(params)
        Helper::SimctlHelper.execute_with_simulator_ready(self, params[:block], params[:runtime], params[:type], params[:name])
      end

      def self.description
        "Fastlane plugin to interact with xcrun simctl."
      end

      def self.authors
        ["Renzo Crisostomo"]
      end

      def self.details
        "Fastlane plugin to interact with xcrun simctl. Manage your iOS Simulators directly from your Fastfile."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :block,
                               description: "A Ruby block given to execute in the context of a Simulator ready",
                                  optional: false,
                                      type: Proc),
          FastlaneCore::ConfigItem.new(key: :runtime,
                               description: "iOS Runtime used to create the simulator",
                                  optional: true,
                                      type: String,
                             default_value: 'latest'),
          FastlaneCore::ConfigItem.new(key: :type,
                               description: "iOS device type used to create the simulator",
                                  optional: true,
                                      type: String,
                             default_value: 'iPhone 6'),
          FastlaneCore::ConfigItem.new(key: :name,
                               description: "String used to set the name to the simulator",
                                  optional: true,
                                      type: String,
                             default_value: nil)
        ]
      end

      def self.is_supported?(platform)
        [:ios].include?(platform)
      end
    end
  end
end
