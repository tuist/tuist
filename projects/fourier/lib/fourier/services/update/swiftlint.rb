# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "down"

module Fourier
  module Services
    module Update
      class Swiftlint < Base
        VERSION = "0.45.0"
        PORTABLE_BINARY_URL = "https://github.com/realm/SwiftLint/releases/download/#{VERSION}/portable_swiftlint.zip"
        OUTPUT_DIRECTORY_FOURIER = File.join(Constants::VENDOR_DIRECTORY, "swiftlint")

        def call
          Dir.mktmpdir do |temporary_dir|
            binary_zip_path = download(temporary_dir: temporary_dir)
            binary_directory_path = extract(binary_zip_path)
            FileUtils.chmod("u=rwx", File.join(binary_directory_path, "swiftlint"))
            FileUtils.copy_entry(binary_directory_path, OUTPUT_DIRECTORY_FOURIER, false, false, true)
          end
        end

        def download(temporary_dir:)
          puts(::CLI::UI.fmt("Downloading the binary from {{info:#{PORTABLE_BINARY_URL}}}"))
          binary_zip_path = File.join(temporary_dir, "swiftlint.zip")
          Down.download(PORTABLE_BINARY_URL, destination: binary_zip_path)
          binary_zip_path
        end

        def extract(binary_zip_path)
          puts("Extracting the binary...")
          zip_content_path = File.join(File.dirname(binary_zip_path), "bin")
          Utilities::Zip.extract(zip: binary_zip_path, into: zip_content_path)
          zip_content_path
        end
      end
    end
  end
end
