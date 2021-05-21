# frozen_string_literal: true
require "fileutils"
require "tmpdir"

module Fourier
  module Services
    module Bundle
      class Tuist < Base
        attr_reader :output_directory
        attr_reader :build_directory

        def initialize(output_directory:, build_directory: nil)
          @output_directory = output_directory
          @build_directory = build_directory
        end

        def call
          output_directory = File.expand_path("build", Constants::ROOT_DIRECTORY) if output_directory.nil?
          FileUtils.mkdir_p(output_directory) unless Dir.exist?(output_directory)

          in_build_directory do |build_directory|
            Utilities::Output.section("Building Tuist...")
            build_tuist(build_directory: build_directory)

            Utilities::Output.section("Building ProjectAutomation...")
            build_project_automation(build_directory: build_directory)

            Utilities::Output.section("Building ProjectDescription...")
            build_project_description(build_directory: build_directory)

            Dir.mktmpdir do |vendor_directory|
              FileUtils.cp_r(
                File.expand_path("projects/tuist/vendor", Constants::ROOT_DIRECTORY),
                File.expand_path("vendor", vendor_directory)
              )
              FileUtils.cp_r(
                File.expand_path("Templates", Constants::ROOT_DIRECTORY),
                File.expand_path("Templates", vendor_directory)
              )
              [
                "tuist", "ProjectDescription.swiftmodule", "ProjectDescription.swiftdoc",
                "libProjectDescription.dylib", "ProjectDescription.swiftinterface",
                "ProjectAutomation.swiftmodule", "ProjectAutomation.swiftdoc", "ProjectAutomation.swiftinterface"
              ].each do |file|
                FileUtils.cp(
                  File.expand_path("release/#{file}", build_directory),
                  File.expand_path(file, vendor_directory)
                )
              end

              Dir.chdir(vendor_directory) do
                output_zip_path = File.expand_path("tuist.zip", output_directory)
                Utilities::Output.section("Generating #{output_zip_path}...")
                Utilities::System.system(
                  "zip", "-q", "-r", "--symlinks",
                  output_zip_path,
                  "tuist",
                  "ProjectDescription.swiftmodule",
                  "ProjectDescription.swiftdoc",
                  "libProjectDescription.dylib",
                  "ProjectDescription.swiftinterface",
                  "ProjectAutomation.swiftmodule",
                  "ProjectAutomation.swiftdoc",
                  "ProjectAutomation.swiftinterface",
                  "Templates",
                  "vendor"
                )
              end
            end
          end
        end

        private
          def in_build_directory
            unless build_directory.nil?
              yield(build_directory)
            else
              Dir.mktmpdir do |tmp_dir|
                yield(tmp_dir)
              end
            end
          end

          def build_tuist(build_directory:)
            Utilities::System.system(
              "swift", "build",
              "--product", "tuist",
              "--configuration", "release",
              "--build-path", build_directory,
              "--package-path", Constants::ROOT_DIRECTORY
            )
          end

          def build_project_description(build_directory:)
            Utilities::System.system(
              "swift", "build",
              "--product", "ProjectDescription",
              "--configuration", "release",
              "-Xswiftc", "-enable-library-evolution",
              "-Xswiftc", "-emit-module-interface",
              "-Xswiftc", "-emit-module-interface-path",
              "-Xswiftc", File.expand_path("release/ProjectDescription.swiftinterface", build_directory),
              "--build-path", build_directory,
              "--package-path", Constants::ROOT_DIRECTORY
            )
          end

          def build_project_automation(build_directory:)
            Utilities::System.system(
              "swift", "build",
              "--product", "ProjectAutomation",
              "--configuration", "release",
              "-Xswiftc", "-enable-library-evolution",
              "-Xswiftc", "-emit-module-interface",
              "-Xswiftc", "-emit-module-interface-path",
              "-Xswiftc", File.expand_path("release/ProjectAutomation.swiftinterface", build_directory),
              "--build-path", build_directory,
              "--package-path", Constants::ROOT_DIRECTORY
            )
          end
      end
    end
  end
end
