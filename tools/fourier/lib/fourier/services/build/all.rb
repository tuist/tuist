# frozen_string_literal: true
module Fourier
  module Services
    module Build
      class All < Base
        def call
          Utilities::System.tuist("build")
        end
      end
    end
  end
end
