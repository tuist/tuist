# frozen_string_literal: true

module Fourier
  module Services
    module Build
      module Tuist
        class All < Base
          def call
            Utilities::System.tuist("fetch")
            Utilities::System.tuist("build", "--generate")
          end
        end
      end
    end
  end
end
