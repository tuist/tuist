# frozen_string_literal: true

require "fileutils"
require "json"

module Fourier
  module Utilities
    module SwiftPackageManager
      ARM64_TARGET = "arm64-apple-macosx"
      X86_64_TARGET = "x86_64-apple-macosx"

      def self.build_product(product)
        Utilities::System.system(
          "swift", "build",
          "--product", product
        )
      end

      def self.build_fat_release_library(
        path:,
        product:,
        output_directory:,
        swift_build_directory:,
        xcode_version:,
        xcode_version_libraries:
      )
        xcode_path = path_to_xcode(xcode_version)
        xcode_path_frameworks = path_to_xcode(xcode_version_libraries || xcode_version)

        Dir.chdir(path) do
          if xcode_path_frameworks != path_to_xcode
            puts "Switching to #{xcode_path_frameworks}"
            Utilities::System.system("sudo xcode-select -switch #{xcode_path_frameworks}")
          end

          Utilities::System.system(
            "xcodebuild",
            "-scheme", product,
            "-configuration", "Release",
            "-destination", "platform=macosx",
            "BUILD_LIBRARY_FOR_DISTRIBUTION=YES",
            "ARCHS=arm64 x86_64",
            "BUILD_DIR=#{swift_build_directory}",
            "clean", "build"
          )

          if xcode_path != path_to_xcode
            puts "Switching back to #{xcode_path}"
            Utilities::System.system("sudo xcode-select -switch #{xcode_path}")
          end

          FileUtils.cp_r(
            File.join(swift_build_directory, "Release/PackageFrameworks/#{product}.framework"),
            File.join(output_directory, "#{product}.framework")
          )
          FileUtils.mkdir_p(File.join(output_directory, "#{product}.framework/Modules"))
          FileUtils.cp_r(
            File.join(swift_build_directory, "Release/#{product}.swiftmodule"),
            File.join(output_directory, "#{product}.framework/Modules/#{product}.swiftmodule")
          )
          FileUtils.cp_r(
            File.join(swift_build_directory, "Release/#{product}.framework.dSYM"),
            File.join(output_directory, "#{product}.framework.dSYM")
          )
        end
      end

      def self.build_fat_release_binary(
        path:,
        product:,
        binary_name:,
        output_directory:,
        swift_build_directory:,
        xcode_version:,
        xcode_version_libraries:,
        additional_options: []
      )
        xcode_path = path_to_xcode(xcode_version)
        if xcode_path != path_to_xcode
          puts "Switching to #{xcode_path}"
          Utilities::System.system("sudo xcode-select -switch #{xcode_path}")
        end

        command = [
          "swift", "build",
          "--configuration", "release",
          "--disable-sandbox",
          "--package-path", path,
          "--product", product,
          "--build-path", swift_build_directory,
        ]

        arm_64 = [*command, "--triple", ARM64_TARGET]
        Utilities::System.system(*arm_64)

        x86 = [*command, "--triple", X86_64_TARGET]
        Utilities::System.system(*x86)

        unless File.exist?(output_directory)
          Dir.mkdir(output_directory)
        end
        Utilities::System.system(
          "lipo", "-create", "-output", File.expand_path(binary_name, output_directory),
          File.join(swift_build_directory, "#{ARM64_TARGET}/release/#{binary_name}"),
          File.join(swift_build_directory, "#{X86_64_TARGET}/release/#{binary_name}")
        )
      end

      private
        def self.path_to_xcode(version = nil)
          # If no Xcode version is provided, return the path to the currently selected version.
          version ||= %x{ xcode-select -p }.split(/(?<=app)/).first

          if !(version =~ /.app/).nil?
            # If the version contains ".app", we can safely assume it's a path
            # to an Xcode app bundle, so we return it.
            version
          else
            # If the version string provided does not contain ".app", it's most likely
            # a version number. We then find the path to the app bundle by parsing the
            # output of the the `system_profiler` binary.
            xcode_infos_json = %x{ system_profiler -json SPDeveloperToolsDataType }
            xcode_infos_hash = JSON.parse(xcode_infos_json)
            xcode_infos = xcode_infos_hash&.dig("SPDeveloperToolsDataType")

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
