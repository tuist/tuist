# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    class UpTest < TestCase
      include TestHelpers::SupressOutput

      def test_call_installs_git_hooks
        # Given
        src_path = File.join(Constants::ROOT_DIRECTORY, "hooks/pre-commit")
        dst_path = File.join(Constants::ROOT_DIRECTORY, ".git/hooks/pre-commit")
        FileUtils
          .expects(:cp)
          .with(src_path, dst_path)
        Utilities::System
          .expects(:system)
          .with("chmod", "u+x", dst_path)

        # When/Then
        supressing_output do
          Up.call
        end
      end
    end
  end
end
