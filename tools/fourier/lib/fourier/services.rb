# frozen_string_literal: true
module Fourier
  module Services
    autoload :Base, "fourier/services/base"
    autoload :Build, "fourier/services/build"
    autoload :Test, "fourier/services/test"
    autoload :GitHub, "fourier/services/github"
    autoload :Generate, "fourier/services/generate"
  end
end
