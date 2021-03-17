# frozen_string_literal: true
module Fourier
  module Commands
    class Lint < Base
      desc "tuist", "Lint the source code of the Tuist CLI"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def tuist
        Services::Lint::Tuist.call(fix: options[:fix])
      end

      desc "fourier", "Lint the source code of the Fourier CLI"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def fourier
        Services::Lint::Fourier.call(fix: options[:fix])
      end
    end
  end
end
