# frozen_string_literal: true

require "test_helper"

module Fourier
  module Utilities
    class ZipTest < TestCase
      include TestHelpers::TemporaryDirectory

      def test_extract
        # Given
        source_dir = File.join(@tmp_dir, "source")
        FileUtils.mkdir_p(source_dir)
        source_file = File.join(source_dir, "test")
        FileUtils.touch(source_file)
        source_zip_file = File.join(source_dir, "test.zip")
        dst_dir = File.join(@tmp_dir, "dst")
        Dir.chdir(source_dir) do
          Utilities::System.system("zip", source_zip_file, "test")
        end

        # When
        Utilities::Zip.extract(
          zip: source_zip_file,
          into: dst_dir
        )

        # Then
        test_file = File.join(dst_dir, "test")

        assert_path_exists(test_file)
      end
    end
  end
end
