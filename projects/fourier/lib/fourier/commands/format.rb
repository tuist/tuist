# frozen_string_literal: true
module Fourier
  module Commands
    class Format < Base
      desc "tuist", "Format the source code of the Tuist CLI"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def tuist
        Services::Format::Tuist.call(fix: options[:fix])
      end
    end
  end
end
