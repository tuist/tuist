# frozen_string_literal: true
module Fourier
  module Commands
    class Serve < Base
      desc "web", "Serve the website"
      def web
        Services::Serve::Web.call
      end

      desc "next", "Serve the next website"
      def next
        Services::Serve::Next.call
      end

      desc "docs", "Serve the documentation website"
      def docs
        Services::Serve::Docs.call
      end
    end
  end
end
