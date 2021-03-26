# frozen_string_literal: true
require "test_helper"
require "down"
require "fileutils"

module Fourier
  module Services
    module Update
      class SwiftdocTest < TestCase
        include TestHelpers::TemporaryDirectory

        def test_call
          # Given
          temporary_dir = File.join(@tmp_dir, "temporary_dir")
          temporary_output_directory = File.join(@tmp_dir, "temporary_output_directory")
          zip_path = File.join(temporary_dir, "swiftdoc.zip")
          content_path = File.join(temporary_dir, "content")
          FileUtils.mkdir_p(content_path)
          sources_path = File.join(content_path, "swiftdoc/")
          FileUtils.mkdir_p(sources_path)
          toolchain_path = File.join(@tmp_dir, "xcode.xctoolchain")
          swift_syntax_parser_dlyb_path = File.join(toolchain_path, "lib_InternalSwiftSyntaxParser.dylib")

          Dir
            .expects(:mktmpdir)
            .twice
            .yields(temporary_dir)
            .then
            .yields(temporary_output_directory)
          Down
            .expects(:download)
            .with(Swiftdoc::SOURCE_TAR_URL, destination: zip_path)
          Utilities::Zip
            .expects(:extract)
            .with(zip: zip_path, into: content_path)
          Utilities::SwiftPackageManager
            .expects(:build_fat_release_binary)
            .with(
              path: sources_path,
              binary_name: 'swift-doc',
              output_directory: temporary_output_directory
            )
          FileUtils
            .expects(:copy_entry)
            .with(
              File.join(sources_path, ".build/arm64-apple-macosx/release/swift-doc_swift-doc.bundle"),
              File.join(temporary_output_directory, "swift-doc_swift-doc.bundle")
            )
          FileUtils
            .expects(:copy_entry)
            .with(
              File.join(sources_path, "LICENSE.md"),
              File.join(temporary_output_directory, "LICENSE.md")
            )
          macho_file = mock("macho_file").responds_like_instance_of(MachO::FatFile)
          MachO::FatFile
            .expects(:new)
            .returns(macho_file)
          macho_file
            .expects(:rpaths)
            .returns([toolchain_path])
          FileUtils
            .expects(:copy_entry)
            .with(
              swift_syntax_parser_dlyb_path,
              File.join(temporary_output_directory, File.basename(swift_syntax_parser_dlyb_path))
            )
          FileUtils
            .expects(:copy_entry)
            .with(
              temporary_output_directory,
              Swiftdoc::OUTPUT_DIRECTORY,
              false, false, true
            )
          # When/Then
          Swiftdoc.call
        end
      end
    end
  end
end
