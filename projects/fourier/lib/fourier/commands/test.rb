# frozen_string_literal: true
module Fourier
  module Commands
    class Test < Base
      desc "tuist SUBCOMMAND ...ARGS", "Run Tuist tests"
      subcommand "tuist", Commands::Test::Tuist
    end
  end
end
