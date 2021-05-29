# frozen_string_literal: true
module Fourier
  module Commands
    class Format < Base
      desc "swift", "Format the Swift code of the repo"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def swift
        Services::Format::Swift.call(fix: options[:fix])
      end
    end
  end
end
