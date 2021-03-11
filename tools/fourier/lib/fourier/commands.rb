# frozen_string_literal: true
module Fourier
  module Commands
    autoload :Base,       "fourier/commands/base"
    autoload :Test,       "fourier/commands/test"
    autoload :Build,      "fourier/commands/build"
    autoload :Generate,   "fourier/commands/generate"
    autoload :GitHub,     "fourier/commands/github"
  end
end
