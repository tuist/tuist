# frozen_string_literal: true
module Fourier
  module Commands
    class Test < Base
      autoload :Tuist, "fourier/commands/test/tuist"

      desc "tuist SUBCOMMAND ...ARGS", "Run Tuist tests"
      subcommand "tuist", Commands::Test::Tuist
    end
  end
end
