# frozen_string_literal: true

require "fileutils"

module Fourier
  module Utilities
    module SwiftPackageManager
      ARM64_TARGET = "arm64-apple-macosx"
      X86_64_TARGET = "x86_64-apple-macosx"

      class << self
        def build_product(product)
          Utilities::System.system(
            "swift",
            "build",
            "--product",
            product,
          )
        end

        def build_fat_release_library(
          path:,
          product:,
          output_directory:,
          swift_build_directory:,
          xcode_paths:
        )
          ENV["DEVELOPER_DIR"] = xcode_paths.libraries

          Dir.chdir(path) do
            Utilities::System.system(
              "xcrun",
              "xcodebuild",
              "-resolvePackageDependencies",
            )
            Utilities::System.system(
              "xcrun",
              "xcodebuild",
              "-scheme",
              product,
              "-configuration",
              "Release",
              "-destination",
              "platform=macosx",
              "BUILD_LIBRARY_FOR_DISTRIBUTION=YES",
              "ARCHS=arm64 x86_64",
              "BUILD_DIR=#{swift_build_directory}",
              "clean",
              "build",
            )

            # NOTE: We remove the PRODUCT.swiftmodule/Project directory because
            # this directory contains objects that are not stable across Swift releases.
            # If left in here they manifest as warnings when compiling.
            FileUtils.rm_rf(
              File.join(swift_build_directory, "Release/#{product}.swiftmodule/Project"),
            )
            FileUtils.cp_r(
              File.join(swift_build_directory, "Release/PackageFrameworks/#{product}.framework"),
              File.join(output_directory, "#{product}.framework"),
            )

            FileUtils.mkdir_p(
              File.join(output_directory, "#{product}.framework/Modules"),
            )
            FileUtils.cp_r(
              File.join(swift_build_directory, "Release/#{product}.swiftmodule"),
              File.join(output_directory, "#{product}.framework/Modules/#{product}.swiftmodule"),
            )

            FileUtils.cp_r(
              File.join(swift_build_directory, "Release/#{product}.framework.dSYM"),
              File.join(output_directory, "#{product}.framework.dSYM"),
            )
          end
        end

        def build_fat_release_binary(
          path:,
          product:,
          binary_name:,
          output_directory:,
          swift_build_directory:,
          xcode_paths:,
          additional_options: []
        )
          ENV["DEVELOPER_DIR"] = xcode_paths.default

          command = [
            "swift",
            "build",
            "--configuration",
            "release",
            "--disable-sandbox",
            "--package-path",
            path,
            "--product",
            product,
            "--build-path",
            swift_build_directory,
          ]

          arm_64 = [*command, "--triple", ARM64_TARGET]
          Utilities::System.system(*arm_64)

          x86 = [*command, "--triple", X86_64_TARGET]
          Utilities::System.system(*x86)

          unless File.exist?(output_directory)
            Dir.mkdir(output_directory)
          end
          Utilities::System.system(
            "lipo",
            "-create",
            "-output",
            File.expand_path(binary_name, output_directory),
            File.join(swift_build_directory, "#{ARM64_TARGET}/release/#{binary_name}"),
            File.join(swift_build_directory, "#{X86_64_TARGET}/release/#{binary_name}"),
          )
        end
      end
    end
  end
end
