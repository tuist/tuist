# frozen_string_literal: true

module Fourier
  module Commands
    class Build < Base
      desc "tuist SUBCOMMAND ...ARGS", "Build Tuist"
      subcommand "tuist", Commands::Build::Tuist

      desc "benchmark", "Build the benchmarking tool"
      def benchmark
        Services::Build::Benchmark.call
      end

      desc "fixture", "Build the fixture generator"
      def fixture
        Services::Build::Fixture.call
      end
    end
  end
end
