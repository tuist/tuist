# frozen_string_literal: true

module Fourier
  module Commands
    class Test < Base
      class Tuist < Base
        desc "unit", "Run Tuist unit tests"
        option(
          :source,
          desc: "Builds Tuist from source and uses that to run the Tuist project unit tests.",
          type: :boolean,
          required: false
        )
        def unit
          Services::Test::Tuist::Unit.call(source: options[:source])
        end

        desc "support", "Run TuistSupport unit tests"
        option(
          :source,
          desc: "Builds Tuist from source and uses that to run the TuistSupport unit tests.",
          type: :boolean,
          required: false
        )
        def support
          Services::Test::Tuist::Support.call(source: options[:source])
        end

        desc "acceptance FEATURE", "Runs the acceptance tests for a given feature."\
          " When no feature is given, it runs the acceptance tests for all the features."
        def acceptance(feature = nil)
          Services::Test::Tuist::Acceptance.call(feature: feature)
        end
      end
    end
  end
end
