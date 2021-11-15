# frozen_string_literal: true

module Fourier
  module Services
    module Build
      module Tuist
        class All < Base
          def call
            dependencies = ["dependencies", "fetch"]
            Utilities::System.tuist(*dependencies)

            Utilities::System.tuist("build", "--generate")
          end
        end
      end
    end
  end
end
