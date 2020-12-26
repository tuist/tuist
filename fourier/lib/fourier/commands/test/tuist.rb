# frozen_string_literal: true
module Fourier
  module Commands
    class Test < Base
      class Tuist < Base
        desc "unit", "Run Tuist unit tests"
        def unit
          Utilities::System.system("swift", "test", "--package-path", File.expand_path("../../../../../", __dir__))
        end
      end
    end
  end
end
