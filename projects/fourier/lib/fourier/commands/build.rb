# frozen_string_literal: true

module Fourier
  module Commands
    class Build < Base
      desc "tuist SUBCOMMAND ...ARGS", "Build Tuist"
      subcommand "tuist", Commands::Build::Tuist
    end
  end
end
