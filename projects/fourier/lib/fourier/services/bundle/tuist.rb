# frozen_string_literal: true
require "fileutils"
require "tmpdir"

module Fourier
  module Services
    module Bundle
      class Tuist < Base
        attr_reader :output_directory

        def initialize(output_directory:)
          @output_directory = output_directory
        end

        def call
          output_directory = File.expand_path("build", Constants::ROOT_DIRECTORY) if output_directory.nil?
          FileUtils.mkdir_p(output_directory) unless Dir.exist?(output_directory)

          Dir.mktmpdir do |build_directory|
            Dir.mktmpdir do |swift_build_directory|
              build_project_library(name: "ProjectDescription", output_directory: build_directory,
                swift_build_directory: swift_build_directory)
              build_project_library(name: "ProjectAutomation", output_directory: build_directory,
                swift_build_directory: swift_build_directory)

              Utilities::Output.section("Building Tuist...")
              build_tuist(output_directory: build_directory, swift_build_directory: swift_build_directory)

              FileUtils.cp_r(
                File.expand_path("projects/tuist/vendor", Constants::ROOT_DIRECTORY),
                File.expand_path("vendor", build_directory)
              )
              FileUtils.cp_r(
                File.expand_path("Templates", Constants::ROOT_DIRECTORY),
                File.expand_path("Templates", build_directory)
              )

              Dir.chdir(build_directory) do
                output_zip_path = File.expand_path("tuist.zip", output_directory)
                Utilities::Output.section("Generating #{output_zip_path}...")
                FileUtils.rm(output_zip_path, force: true)
                Utilities::System.system(
                  "zip", "-q", "-r", "--symlinks",
                  output_zip_path,
                  "tuist",
                  "ProjectDescription.framework",
                  "ProjectDescription.framework.dSYM",
                  "ProjectAutomation.framework",
                  "ProjectAutomation.framework.dSYM",
                  "Templates",
                  "vendor"
                )
              end
            end
          end
        end

        private
          def build_tuist(output_directory:, swift_build_directory:)
            Utilities::SwiftPackageManager.build_fat_release_binary(
              path: Constants::ROOT_DIRECTORY,
              product: "tuist",
              binary_name: "tuist",
              output_directory: output_directory,
              swift_build_directory: swift_build_directory
            )
          end

          def build_project_library(name:, output_directory:, swift_build_directory:)
            Utilities::Output.section("Building #{name}...")
            Utilities::SwiftPackageManager.build_fat_release_library(
              path: Constants::ROOT_DIRECTORY,
              product: name,
              output_directory: output_directory,
              swift_build_directory: swift_build_directory
            )
          end
      end
    end
  end
end
