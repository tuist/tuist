# frozen_string_literal: true

module Fourier
  module Commands
    class Test < Base
      class Tuist < Base
        desc "unit", "Run Tuist unit tests"
        def unit
          Services::Test::Tuist::Unit.call
        end

        desc "support", "Run TuistSupport unit tests"
        def support
          Services::Test::Tuist::Support.call
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
