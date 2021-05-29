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

          in_build_directory do |build_directory|
            Utilities::Output.section("Building Tuistenv...")
            build_tuistenv(build_directory: build_directory)

            Dir.mktmpdir do |vendor_directory|
              FileUtils.cp(
                File.expand_path("release/tuistenv", build_directory),
                File.expand_path("tuistenv", vendor_directory)
              )

              Dir.chdir(vendor_directory) do
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
          def in_build_directory
            unless build_directory.nil?
              yield(build_directory)
            else
              Dir.mktmpdir do |tmp_dir|
                yield(tmp_dir)
              end
            end
          end

          def build_tuistenv(build_directory:)
            Utilities::System.system(
              "swift", "build",
              "--product", "tuistenv",
              "--configuration", "release",
              "--build-path", build_directory,
              "--package-path", Constants::ROOT_DIRECTORY
            )
          end
      end
    end
  end
end
