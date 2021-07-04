# frozen_string_literal: true
require "fileutils"
require "tmpdir"

module Fourier
  module Services
    module Bundle
      class Tuistenv < Base
        attr_reader :output_directory
        attr_reader :build_directory

        def initialize(output_directory:, build_directory: nil)
          @output_directory = output_directory
          @build_directory = build_directory
        end

        def call
          output_directory = File.expand_path("build", Constants::ROOT_DIRECTORY) if output_directory.nil?
          FileUtils.mkdir_p(output_directory) unless Dir.exist?(output_directory)

          Dir.mktmpdir do |build_directory|
            Dir.mktmpdir do |swift_build_directory|
              Utilities::Output.section("Building Tuistenv...")
              build_tuistenv(
                output_directory: build_directory,
                swift_build_directory: swift_build_directory
              )

              Dir.chdir(build_directory) do
                output_zip_path = File.expand_path("tuistenv.zip", output_directory)
                Utilities::Output.section("Generating #{output_zip_path}...")

                Utilities::System.system(
                  "zip", "-q", "-r", "--symlinks",
                  output_zip_path,
                  "tuistenv"
                )
              end
            end
          end
        end

        private
          def build_tuistenv(output_directory:, swift_build_directory:)
            Utilities::SwiftPackageManager.build_fat_release_binary(
              path: Constants::ROOT_DIRECTORY,
              product: "tuistenv",
              binary_name: "tuistenv",
              output_directory: output_directory,
              swift_build_directory: swift_build_directory
            )
          end
      end
    end
  end
end
