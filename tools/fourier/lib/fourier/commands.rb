# frozen_string_literal: true
require "thor"

module Fourier
  module Commands
    autoload :Base, "fourier/commands/base"
    autoload :Test, "fourier/commands/test"
  end
end
