# frozen_string_literal: true
module Fourier
  module Services
    module Test
      module Tuist
        autoload :Unit,       "fourier/services/test/tuist/unit"
        autoload :Acceptance, "fourier/services/test/tuist/acceptance"
      end
    end
  end
end
