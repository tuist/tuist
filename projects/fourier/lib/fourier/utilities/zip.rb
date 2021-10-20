# frozen_string_literal: true

require "fileutils"
require "zip"

module Fourier
  module Utilities
    module Zip
      def self.extract(zip:, into:)
        FileUtils.rm_rf(into) if Dir.exist?(into)
        FileUtils.mkdir_p(into)

        ::Zip::File.open(zip) do |zip_file|
          zip_file.each do |f|
            fpath = File.join(into, f.name)
            zip_file.extract(f, fpath) unless File.exist?(fpath)
          end
        end
      end
    end
  end
end
