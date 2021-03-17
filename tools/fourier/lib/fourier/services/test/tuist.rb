# frozen_string_literal: true
module Fourier
  module Services
    module Test
      module Tuist
        autoload :Unit,       "fourier/services/test/tuist/unit"
        autoload :Support,    "fourier/services/test/tuist/support"
        autoload :Acceptance, "fourier/services/test/tuist/acceptance"
      end
    end
  end
end
