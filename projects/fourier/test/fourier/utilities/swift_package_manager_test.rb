# frozen_string_literal: true
require "test_helper"

module Fourier
  module Utilities
    class SwiftPackageManagerTest < TestCase
      def test_build_fat_release_binary
        # Given
        binary_name = "tuist"
        path = "/tmp/tuist"
        output_directory = "/tmp/output"
        expected_command = [
          "swift", "build",
          "--configuration", "release",
          "--disable-sandbox",
          "--package-path", path
        ]
        expected_arm64_command = [*expected_command, "--triple", "arm64-apple-macosx"]
        expected_x86_command = [*expected_command, "--triple", "x86_64-apple-macosx"]
        expected_lipo_command = [
          "lipo", "-create", "-output", File.join(output_directory, binary_name),
          File.join(path, ".build/arm64-apple-macosx/release/tuist"),
          File.join(path, ".build/x86_64-apple-macosx/release/tuist")
        ]
        Utilities::System
          .expects(:system)
          .with(*expected_arm64_command)
        Utilities::System
          .expects(:system)
          .with(*expected_x86_command)
        Utilities::System
          .expects(:system)
          .with(*expected_lipo_command)

        Utilities::SwiftPackageManager.build_fat_release_binary(
          path: path,
          binary_name: binary_name,
          output_directory: output_directory
        )
      end
    end
  end
end
