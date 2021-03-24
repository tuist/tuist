# frozen_string_literal: true

module Fourier
  module Services
    module Update
      class Xcbeautify < Base
        def call
          # XCBEAUTIFY_VERSION = "0.9.1"

          # root_dir = File.expand_path(__dir__)
          # Dir.mktmpdir do |temporary_dir|
          #   Dir.chdir(temporary_dir) do
          #     system("curl", "-LO", "https://github.com/thii/xcbeautify/archive/#{XCBEAUTIFY_VERSION}.zip")
          #     extract_zip("#{XCBEAUTIFY_VERSION}.zip", "xcbeautify")
          #     Dir.chdir("xcbeautify/xcbeautify-#{XCBEAUTIFY_VERSION}") do
          #       system("make", "build")
          #     end
          #     release_dir = File.join(temporary_dir,
          #       "xcbeautify/xcbeautify-#{XCBEAUTIFY_VERSION}/.build/release")
          #     vendor_dir = File.join(root_dir, "vendor")
          #     dst_binary_path = File.join(vendor_dir, "xcbeautify")

          #     # Copy binary
          #     binary_path = File.join(release_dir, "xcbeautify")
          #     File.delete(dst_binary_path) if File.exist?(dst_binary_path)
          #     FileUtils.cp(binary_path, dst_binary_path)
          #   end
          # end
          # # Write version
          # File.write(File.join(root_dir, "vendor/.xcbeautify.version"), XCBEAUTIFY_VERSION)
        end
      end
    end
  end
end
