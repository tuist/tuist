# frozen_string_literal: true

module Fourier
  module Services
    class Up < Base
      def call
        install_git_hooks
      end

      private
        def install_git_hooks
          Utilities::Output.section("Installing Git pre-commit hooks")
          src_path = File.join(Constants::ROOT_DIRECTORY, "hooks/pre-commit")
          dst_path = File.join(Constants::ROOT_DIRECTORY, ".git/hooks/pre-commit")

          FileUtils.cp(src_path, dst_path)
          Utilities::System.system("chmod", "u+x", dst_path)
        end
    end
  end
end
