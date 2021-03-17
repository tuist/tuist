# frozen_string_literal: true
module Fourier
  module Commands
    class Format < Base
      desc "tuist", "Format the source code of the Tuist CLI"
      def tuist
        Services::Format::Tuist.call
      end
    end
  end
end
