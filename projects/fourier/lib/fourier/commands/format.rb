# frozen_string_literal: true
module Fourier
  module Commands
    class Format < Base
      desc "swift", "Format the Swift code of the repo"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def swift
        exit_status = Services::Format::Swift.call(fix: options[:fix])
        if !options[:fix] && !exit_status
          puts(::CLI::UI.fmt("{{red:Please run `./fourier format swift --fix` to address Swift formatting issues.}}"))
        end
      end
    end
  end
end
