# frozen_string_literal: true
require 'tmpdir'

module Fourier
  module Services
    module Update
      class Swiftdoc < Base
        def call
          output_directory = File.join(Constants::VENDOR_DIRECTORY, "swift-doc")

          Dir.mktmpdir do |temporary_dir|
            Dir.chdir(temporary_dir) do
              system("curl", "-LO", "https://github.com/SwiftDocOrg/swift-doc/archive/#{SWIFTDOC_VERSION}.zip")
              extract_zip("#{SWIFTDOC_VERSION}.zip", "swift-doc")
              Dir.chdir("swift-doc/swift-doc-#{SWIFTDOC_VERSION}") do
                system("make", "swift-doc")
              end
              release_dir = File.join(temporary_dir, "swift-doc/swift-doc-#{SWIFTDOC_VERSION}/.build/release/")
              vendor_dir = File.join(root_dir, "vendor")
              dst_binary_path = File.join(vendor_dir, "swift-doc")
              bundle_paths = Dir[File.join(release_dir, "*.bundle")]

              # Copy binary and bundles
              binary_path = File.join(release_dir, "swift-doc")
              File.delete(dst_binary_path) if File.exist?(dst_binary_path)
              FileUtils.cp(binary_path, dst_binary_path)
              bundle_paths.each do |bundle_path|
                bundle_dst_path = File.join(vendor_dir, File.basename(bundle_path))
                FileUtils.rm_rf(bundle_dst_path) if File.exist?(bundle_dst_path)
                FileUtils.cp_r(bundle_path, bundle_dst_path)
              end

              # Change the reference to lib_InternalSwiftSyntaxParser.dylib
              # https://github.com/SwiftDocOrg/homebrew-formulae/blob/master/Formula/swift-doc.rb#L43
              macho = MachO.open(dst_binary_path)
              break unless (toolchain = macho.rpaths.find { |path| path.include?(".xctoolchain") })
              syntax_parser_dylib_name = "lib_InternalSwiftSyntaxParser.dylib"
              FileUtils.cp(File.join(toolchain, syntax_parser_dylib_name), File.join(vendor_dir, syntax_parser_dylib_name))

              # Write version
              File.write(File.join(root_dir, "vendor/.swiftdoc.version"), SWIFTDOC_VERSION)
            end
          end
        end
      end
    end
  end
end
