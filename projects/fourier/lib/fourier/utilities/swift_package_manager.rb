# frozen_string_literal: true
module Fourier
  module Utilities
    module SwiftPackageManager
      def self.build_fat_release_binary(path:, product:, binary_name:, output_directory:, additional_options: [])
        command = [
          "swift", "build",
          "--configuration", "release",
          "--disable-sandbox",
          "--package-path", path,
          "--product", product
        ]

        unless additional_options.empty?
          command += additional_options
        end

        arm_64 = [*command, "--triple", "arm64-apple-macosx"]
        Utilities::System.system(*arm_64)

        x86 = [*command, "--triple", "x86_64-apple-macosx"]
        Utilities::System.system(*x86)

        unless File.exist?(output_directory)
          Dir.mkdir output_directory
        end
        puts File.expand_path(binary_name, output_directory)
        Utilities::System.system(
          "lipo", "-create", "-output", File.expand_path(binary_name, output_directory),
          File.join(path, ".build/arm64-apple-macosx/release/#{binary_name}"),
          File.join(path, ".build/x86_64-apple-macosx/release/#{binary_name}")
        )
      end
    end
  end
end
