# frozen_string_literal: true

require "json"

module Fourier
  module Utilities
    module Xcode
      def self.current_xcode_version
        %x{ xcode-select -p }.split(/(?<=app)/).first
      end

      def self.switch_xcode_version(xcode_path)
        Utilities::System.system("sudo xcode-select -switch #{xcode_path}")
      end

      def self.path_to_xcode(version)
        if version.nil?
          nil
        elsif !(version =~ /.app/).nil?
          # If the version contains ".app", we can safely assume it's a path
          # to an Xcode app bundle, so we return it.
          version
        else
          # If the version string provided does not contain ".app", it's most likely
          # a version number. We then find the path to the app bundle by parsing the
          # output of the the `system_profiler` binary.
          xcode_infos_json = %x{ system_profiler -json SPDeveloperToolsDataType }
          parsed_xcode_infos = JSON.parse(xcode_infos_json)
          xcode_infos = parsed_xcode_infos&.dig("SPDeveloperToolsDataType")

          desired_xcode = xcode_infos.find { |info|
            xcode_version = info&.dig("spdevtools_version").split(" (").first
            xcode_version == version
          }
          desired_xcode_path = desired_xcode&.dig("spdevtools_path")

          desired_xcode_path ||
            Output.error(message: "The requested Xcode version '#{version}' is not available")
        end
      end
    end
  end
end
