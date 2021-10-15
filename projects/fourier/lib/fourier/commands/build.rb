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

      desc "web", "Build the website"
      def web
        Services::Build::Web.call
      end

      desc "docs", "Build the documentation website"
      def docs
        Services::Build::Docs.call
      end
    end
  end
end
