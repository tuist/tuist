# frozen_string_literal: true
module Fourier
  module Commands
    class Test < Base
      desc "tuist SUBCOMMAND ...ARGS", "Run Tuist tests"
      subcommand "tuist", Commands::Test::Tuist

      desc "fourier TEST", "Run all Fourier tests or the TEST one."
      def fourier(test = nil)
        Services::Test::Fourier.call(test: test)
      end
    end
  end
end
