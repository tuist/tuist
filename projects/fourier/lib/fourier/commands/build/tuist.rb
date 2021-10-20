# frozen_string_literal: true

module Fourier
  module Commands
    class Build < Base
      class Tuist < Base
        desc "support", "Build TuistSupport"
        def support
          Services::Build::Tuist::Support.call
        end

        desc "all", "Build all targets"
        def all
          Services::Build::Tuist::All.call
        end
      end
    end
  end
end
