# frozen_string_literal: true
require "fileutils"

module Fourier
  module Utilities
    module SwiftPackageManager
      ARM64_TARGET = "arm64-apple-macosx"
      X86_64_TARGET = "x86_64-apple-macosx"

      def self.build_fat_release_library(path:, product:, binary_name:, output_directory:, swift_build_directory:)
        FileUtils.mkdir_p(File.expand_path("#{product}.swiftinterface", output_directory))
        FileUtils.mkdir_p(File.expand_path("#{product}.swiftmodule", output_directory))

        self.build_fat_release_binary(
          path: path,
          product: product,
          binary_name: binary_name,
          output_directory: output_directory,
          swift_build_directory: swift_build_directory
        ) do |arch|
          additional_options = [
            "-Xswiftc", "-enable-library-evolution",
            "-Xswiftc", "-emit-module",
            "-Xswiftc", "-emit-module-path",
            "-Xswiftc", File.expand_path("#{product}.swiftmodule/#{arch}.swiftmodule", output_directory),
            "-Xswiftc", "-emit-module-interface",
            "-Xswiftc", "-emit-module-interface-path",
            "-Xswiftc", File.expand_path("#{product}.swiftinterface/#{arch}.swiftinterface", output_directory)
          ]
          additional_options
        end
      end

      def self.build_fat_release_binary(path:, product:, binary_name:, output_directory:, swift_build_directory:)
        command = [
          "swift", "build",
          "--configuration", "release",
          "--disable-sandbox",
          "--package-path", path,
          "--product", product,
          "--build-path", swift_build_directory
        ]

        arm_64 = [*command, "--triple", ARM64_TARGET]
        arm_64 += yield("arm64") if block_given?
        Utilities::System.system(*arm_64)

        x86 = [*command, "--triple", X86_64_TARGET]
        x86 += yield("x86_64") if block_given?
        Utilities::System.system(*x86)

        unless File.exist?(output_directory)
          Dir.mkdir(output_directory)
        end
        Utilities::System.system(
          "lipo", "-create", "-output", File.expand_path(binary_name, output_directory),
          File.join(swift_build_directory, "#{ARM64_TARGET}/release/#{binary_name}"),
          File.join(swift_build_directory, "#{X86_64_TARGET}/release/#{binary_name}")
        )
      end
    end
  end
end
