# frozen_string_literal: true
module Fourier
  module Commands
    class Test < Base
      desc "tuist SUBCOMMAND ...ARGS", "Run Tuist tests"
      subcommand "tuist", Commands::Test::Tuist

      desc "fourier", "Run Fourier tests"
      def fourier
        Services::Test::Fourier.call
      end
    end
  end
end
