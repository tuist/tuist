# frozen_string_literal: true
require "fileutils"
require "zip"

module Fourier
  module Utilities
    module Zip
      def self.extract(zip:, dst_directory:)
        FileUtils.rm_rf(dst_directory) if Dir.exist?(dst_directory)
        FileUtils.mkdir_p(dst_directory)

        ::Zip::File.open(zip) do |zip_file|
          zip_file.each do |f|
            fpath = File.join(dst_directory, f.name)
            zip_file.extract(f, fpath) unless File.exist?(fpath)
          end
        end
      end
    end
  end
end
