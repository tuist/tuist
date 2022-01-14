# frozen_string_literal: true

module Fourier
  module Commands
    class Build < Base
      class Tuist < Base
        desc "support", "Build TuistSupport"
        option(
          :source,
          desc: "Builds Tuist from source and uses that to focus on the targets.",
          type: :boolean,
          required: false
        )
        def support
          Services::Build::Tuist::Support.call(source: options[:source])
        end

        desc "all", "Build all targets"
        option(
          :source,
          desc: "Builds Tuist from source and uses that to focus on the targets.",
          type: :boolean,
          required: false
        )
        def all
          Services::Build::Tuist::All.call(source: options[:source])
        end
      end
    end
  end
end
