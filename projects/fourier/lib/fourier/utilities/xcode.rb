# frozen_string_literal: true

require "json"

module Fourier
  module Utilities
    module Xcode
      def self.current_xcode_version
        %x{ xcode-select -p }.split(/(?<=app)/).first
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
            SemVer.new(xcode_version) == SemVer.new(version)
          }
          desired_xcode_path = desired_xcode&.dig("spdevtools_path")

          if desired_xcode_path.nil?
            Output.error("The requested Xcode version '#{version}' is not available")
            exit(1)
          else
            desired_xcode_path
          end
        end
      end

      class Paths
        attr_accessor :default
        attr_accessor :libraries

        def initialize(default:, libraries:)
          @default   = Xcode.path_to_xcode(default)   || Xcode.current_xcode_version
          @libraries = Xcode.path_to_xcode(libraries) || @default
        end
      end

      class SemVer
        attr_accessor :major
        attr_accessor :minor
        attr_accessor :patch

        def initialize(version)
          sem_version = version.strip.split(".")
          @major = sem_version[0]
          @minor = sem_version[1] || 0
          @patch = sem_version[2] || 0
        end

        def ==(other)
          self.major == other.major &&
            self.minor == other.minor &&
            self.patch == other.patch
        end
      end
    end
  end
end
