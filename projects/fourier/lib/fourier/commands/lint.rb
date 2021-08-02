# frozen_string_literal: true
module Fourier
  module Commands
    class Lint < Base
      desc "swift", "Lint the Swift code of the project"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def swift
        Services::Lint::Swift.call(fix: options[:fix])
      end

      desc "ruby", "Lint the Ruby code of the project"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def ruby
        Services::Lint::Ruby.call(fix: options[:fix])
      end

      desc "all", "Lint all the code in the repository"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def all
        Services::Lint::Swift.call(fix: options[:fix])
        Services::Lint::Ruby.call(fix: options[:fix])
      end

      desc "lockfiles", "Ensures SPM and Tuist's generated lockfiles are consistent"
      def lockfiles
        Services::Lint::Lockfiles.call
      end
    end
  end
end
