# frozen_string_literal: true
module Fourier
  module Utilities
    module SwiftPackageManager
      def self.build_fat_release_binary(path:, binary_name:, output_directory:)
        command = [
          "swift", "build",
          "--configuration", "release",
          "--disable-sandbox",
          "--package-path", path
        ]

        arm_64 = [*command, "--triple", "arm64-apple-macosx"]
        Utilities::System.system(*arm_64)

        x86 = [*command, "--triple", "x86_64-apple-macosx"]
        Utilities::System.system(*x86)

        Utilities::System.system(
          "lipo", "-create", "-output", File.join(output_directory, binary_name),
          File.join(path, ".build/arm64-apple-macosx/release/swift-doc"),
          File.join(path, ".build/x86_64-apple-macosx/release/swift-doc")
        )
      end
    end
  end
end
