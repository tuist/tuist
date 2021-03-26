# frozen_string_literal: true
require "test_helper"
require "down"

module Fourier
  module Services
    module Update
      class SwiftlintTest < TestCase
        include TestHelpers::TemporaryDirectory

        def test_call
          # Given
          Dir
            .expects(:mktmpdir)
            .yields(@tmp_dir)
          zip_path = File.join(@tmp_dir, "swiftlint.zip")
          content_path = File.join(@tmp_dir, "bin")
          Down
            .expects(:download)
            .with(Swiftlint::PORTABLE_BINARY_URL, destination: zip_path)
          Utilities::Zip
            .expects(:extract)
            .with(zip: zip_path, into: content_path)
          FileUtils
            .expects(:copy_entry)
            .with(content_path, Swiftlint::OUTPUT_DIRECTORY, false, false, true)

          # When
          Services::Update::Swiftlint.call
        end
      end
    end
  end
end
