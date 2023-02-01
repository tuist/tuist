# frozen_string_literal: true

require "tmpdir"
require "down"

module Fourier
  module Services
    module Update
      class Swiftformat < Base
        VERSION = "0.48.18"
        SOURCE_TAR_URL = "https://github.com/nicklockwood/SwiftFormat/archive/refs/tags/#{VERSION}.zip"
        OUTPUT_DIRECTORY = File.join(Constants::VENDOR_DIRECTORY, "swiftformat")

        attr_reader :swift_build_directory

        def initialize(swift_build_directory:)
          @swift_build_directory = swift_build_directory
          super()
        end

        def call
          Dir.mktmpdir do |temporary_dir|
            Dir.mktmpdir do |temporary_output_directory|
              sources_zip_path = download(temporary_dir: temporary_dir)
              sources_path = extract(sources_zip_path)
              build(sources_path, into: temporary_output_directory, swift_build_directory: swift_build_directory)
              FileUtils.copy_entry(
                File.join(sources_path, "LICENSE.md"),
                File.join(temporary_output_directory, "LICENSE.md"))
              FileUtils.copy_entry(temporary_output_directory, OUTPUT_DIRECTORY, false, false, true)
              puts(::CLI::UI.fmt("{{success:swiftformat built and vendored successfully.}}"))
            end
          end
        end

        private
          def download(temporary_dir:)
            puts(::CLI::UI.fmt("Downloading source code from {{info:#{SOURCE_TAR_URL}}}"))
            sources_zip_path = File.join(temporary_dir, "swiftformat.zip")
            Down.download(SOURCE_TAR_URL, destination: sources_zip_path)
            sources_zip_path
          end

          def extract(sources_zip_path)
            puts("Extracting source code...")
            content_path = File.join(File.dirname(sources_zip_path), "content")
            Utilities::Zip.extract(zip: sources_zip_path, into: content_path)
            Dir.glob(File.join(content_path, "*/")).first
          end

          def build(sources_path, into:, swift_build_directory:)
            puts("Building...")
            Utilities::SwiftPackageManager.build_fat_release_binary(
              path: sources_path,
              product: "swiftformat",
              binary_name: "swiftformat",
              output_directory: into,
              swift_build_directory: swift_build_directory,
            )
          end
      end
    end
  end
end
