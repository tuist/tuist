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
            build_project_library(name: "ProjectDescription", build_directory: build_directory)
            build_project_library(name: "ProjectAutomation", build_directory: build_directory)

            Utilities::Output.section("Building Tuist...")
            build_tuist(build_directory: build_directory)

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
                "libProjectAutomation.dylib",
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
                  "libProjectAutomation.dylib",
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
            Utilities::SwiftPackageManager.build_fat_release_binary(
              path: Constants::ROOT_DIRECTORY,
              product: "tuist",
              binary_name: "tuist",
              output_directory: File.join(build_directory, "release")
            )
          end

          def build_project_library(name:, build_directory:)
            Utilities::Output.section("Building #{name}...")
            Utilities::System.system(
              "swift", "build",
              "--product", name,
              "--configuration", "release",
              "--build-path", build_directory,
              "--package-path", Constants::ROOT_DIRECTORY
            )
            Utilities::SwiftPackageManager.build_fat_release_binary(
              path: Constants::ROOT_DIRECTORY,
              product: name,
              binary_name: "lib#{name}.dylib",
              output_directory: File.join(build_directory, "release"),
              additional_options: [
                "-Xswiftc", "-enable-library-evolution",
                "-Xswiftc", "-emit-module-interface",
                "-Xswiftc", "-emit-module-interface-path",
                "-Xswiftc", File.expand_path("release/#{name}.swiftinterface", build_directory),
              ]
            )
          end
      end
    end
  end
end
