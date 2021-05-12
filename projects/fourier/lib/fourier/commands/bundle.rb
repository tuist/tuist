# frozen_string_literal: true
module Fourier
  module Commands
    class Bundle < Base
      desc "tuist", "Bundle tuist"
      def tuist
        Services::Bundle::Tuist.call
      end

      desc "tuistenv", "Bundle tuistenv"
      def tuistenv
        Services::Bundle::Tuistenv.call
      end
    end
  end
end
