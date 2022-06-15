# frozen_string_literal: true

require "test_helper"
require "down"
require "fileutils"

module Fourier
  module Services
    module Update
      class XcbeautifyTest < TestCase
        include TestHelpers::TemporaryDirectory
        include TestHelpers::SupressOutput

        def test_call
          supressing_output do
            # Given
            temporary_dir = File.join(@tmp_dir, "temporary_dir")
            swift_build_directory = File.join(@tmp_dir, "swift_build_directory")
            temporary_output_directory = File.join(@tmp_dir, "temporary_output_directory")
            zip_path = File.join(temporary_dir, "xcbeautify.zip")
            content_path = File.join(temporary_dir, "content")
            FileUtils.mkdir_p(content_path)
            sources_path = File.join(content_path, "xcbeautify/")
            FileUtils.mkdir_p(sources_path)

            Dir
              .expects(:mktmpdir)
              .twice
              .yields(temporary_dir)
              .then
              .yields(temporary_output_directory)
            Down
              .expects(:download)
              .with(Xcbeautify::SOURCE_TAR_URL, destination: zip_path)
            Utilities::Zip
              .expects(:extract)
              .with(zip: zip_path, into: content_path)
            Utilities::SwiftPackageManager
              .expects(:build_fat_release_binary)
              .with(
                path: sources_path,
                product: "xcbeautify",
                binary_name: "xcbeautify",
                output_directory: temporary_output_directory,
                swift_build_directory: swift_build_directory
              )
            FileUtils
              .expects(:copy_entry)
              .with(File.join(sources_path, "LICENSE"), File.join(temporary_output_directory, "LICENSE"))
            FileUtils
              .expects(:copy_entry)
              .with(temporary_output_directory, Xcbeautify::OUTPUT_DIRECTORY, false, false, true)

            # When/then
            Update::Xcbeautify.call(swift_build_directory: swift_build_directory)
          end
        end
      end
    end
  end
end
