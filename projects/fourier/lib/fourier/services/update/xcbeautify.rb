# frozen_string_literal: true
require 'tmpdir'
require 'down'

module Fourier
  module Services
    module Update
      class Xcbeautify < Base
        VERSION = "0.9.1"
        SOURCE_TAR_URL = "https://github.com/thii/xcbeautify/archive/#{VERSION}.zip"

        def call
          output_directory = File.join(Constants::TUIST_VENDOR_DIRECTORY, "xcbeautify")

          Dir.mktmpdir do |temporary_dir|
            Dir.mktmpdir do |temporary_output_directory|
              sources_zip_path = download(temporary_dir: temporary_dir)
              sources_path = extract(sources_zip_path)
              build(sources_path, into: temporary_output_directory)
              FileUtils.copy_entry(File.join(sources_path, "LICENSE"), File.join(temporary_output_directory, "LICENSE"))
              FileUtils.rm_rf(output_directory) if Dir.exist?(output_directory)
              FileUtils.mkdir_p(output_directory)
              FileUtils.copy_entry(temporary_output_directory, output_directory)
              puts(::CLI::UI.fmt("{{success:xcbeautify built and vendored successfully.}}"))
            end
          end
        end

        private

        def download(temporary_dir:)
          puts(::CLI::UI.fmt("Downloading source code from {{info:#{SOURCE_TAR_URL}}}"))
          sources_zip_path = File.join(temporary_dir, "xcbeautify.zip")
          Down.download(SOURCE_TAR_URL, destination: sources_zip_path)
          sources_zip_path
        end

        def extract(sources_zip_path)
          puts("Extracting source code...")
          zip_content_path = File.join(File.dirname(sources_zip_path), "content")
          Utilities::Zip.extract(zip: sources_zip_path, into: zip_content_path)
          Dir.glob(File.join(zip_content_path, "*/")).first
        end

        def build(sources_path, into:)
          puts("Building...")
          Utilities::SwiftPackageManager.build_fat_release_binary(
            path: sources_path,
            binary_name: "xcbeautify",
            output_directory: into
          )
        end
      end
    end
  end
end
