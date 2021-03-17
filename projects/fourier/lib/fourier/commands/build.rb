# frozen_string_literal: true
module Fourier
  module Commands
    class Build < Base
      desc "tuist SUBCOMMAND ...ARGS", "Build Tuist"
      subcommand "tuist", Commands::Build::Tuist

      desc "benchmark", "Build tuistbench"
      def benchmark
        Services::Build::Bench.call
      end
    end
  end
end
