# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Fourier
  module Services
    module Bundle
      class Tuist < Base
        attr_reader :output_directory
        attr_reader :xcode_paths

        def initialize(
          output_directory:,
          xcode_paths:
        )
          @output_directory = output_directory
          @xcode_paths = xcode_paths
        end

        def call
          FileUtils.rm_rf(File.expand_path("Tuist.xcodeproj", Constants::ROOT_DIRECTORY))
          FileUtils.rm_rf(File.expand_path("Tuist.xcworkspace", Constants::ROOT_DIRECTORY))

          output_directory = File.expand_path("build", Constants::ROOT_DIRECTORY) if output_directory.nil?
          FileUtils.mkdir_p(output_directory) unless Dir.exist?(output_directory)

          Dir.mktmpdir do |build_directory|
            Dir.mktmpdir do |swift_build_directory|
              build_project_library(
                name: "ProjectDescription",
                output_directory: build_directory,
                swift_build_directory: swift_build_directory,
                xcode_paths: xcode_paths,
              )

              Utilities::Output.section("Building Tuist...")
              build_tuist(
                output_directory: build_directory,
                swift_build_directory: swift_build_directory,
                xcode_paths: xcode_paths,
              )

              FileUtils.cp_r(
                File.expand_path("projects/tuist/vendor", Constants::ROOT_DIRECTORY),
                File.expand_path("vendor", build_directory),
              )
              FileUtils.cp_r(
                File.expand_path("Templates", Constants::ROOT_DIRECTORY),
                File.expand_path("Templates", build_directory),
              )
              Utilities::System.system(
                "swift",
                "stdlib-tool",
                "--copy",
                "--scan-executable",
                File.expand_path("tuist", build_directory),
                "--platform",
                "macosx",
                "--destination",
                build_directory)

              Dir.chdir(build_directory) do
                output_zip_path = File.expand_path("tuist.zip", output_directory)
                Utilities::Output.section("Generating #{output_zip_path}...")
                FileUtils.rm(output_zip_path, force: true)
                Utilities::System.system(
                  "zip",
                  "-q",
                  "-r",
                  "--symlinks",
                  output_zip_path,
                  "tuist",
                  "libswift_Concurrency.dylib",
                  "ProjectAutomation.framework",
                  "ProjectAutomation.framework.dSYM",
                  "ProjectDescription.framework",
                  "ProjectDescription.framework.dSYM",
                  "Templates",
                  "vendor",
                )
              end
            end
          end
        end

        private
          def build_tuist(
            output_directory:,
            swift_build_directory:,
            xcode_paths:
          )
            Utilities::SwiftPackageManager.build_fat_release_binary(
              path: Constants::ROOT_DIRECTORY,
              product: "tuist",
              binary_name: "tuist",
              output_directory: output_directory,
              swift_build_directory: swift_build_directory,
              xcode_paths: xcode_paths,
            )
          end

          def build_project_library(
            name:,
            output_directory:,
            swift_build_directory:,
            xcode_paths:
          )
            Utilities::Output.section("Building #{name}...")
            Utilities::SwiftPackageManager.build_fat_release_library(
              path: Constants::ROOT_DIRECTORY,
              product: name,
              output_directory: output_directory,
              swift_build_directory: swift_build_directory,
              xcode_paths: xcode_paths,
            )
          end
      end
    end
  end
end
