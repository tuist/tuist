# frozen_string_literal: true

module Fourier
  module Commands
    class Serve < Base
      desc "docs", "Serve the documentation website"
      def docs
        Services::Serve::Docs.call
      end
    end
  end
end
