# frozen_string_literal: true
module Fourier
  module Commands
    class Build < Base
      autoload :Support, "fourier/commands/build/support"

      desc "support", "Build TuistSupport"
      def support
        Services::Build::Support.call
      end

      desc "all", "Build all targets"
      def all
        Services::Build::All.call
      end
    end
  end
end
