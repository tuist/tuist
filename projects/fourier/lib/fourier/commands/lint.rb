# frozen_string_literal: true

module Fourier
  module Commands
    class Lint < Base
      desc "tuist", "Lint the Swift code of the Tuist CLI"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def tuist
        lint_tuist(fix: options[:fix])
      end

      desc "tuistbench", "Lint the Swift code of the tuistbench project"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def tuistbench
        Services::Lint::Tuistbench.call(fix: options[:fix])
      end

      desc "fixturegen", "Lint the Swift code of the fixturegen project"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def fixturegen
        Services::Lint::Fixturegen.call(fix: options[:fix])
      end

      desc "fourier", "Lint the Ruby code of the fixturegen project"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def fourier
        Services::Lint::Fourier.call(fix: options[:fix])
      end

      desc "lockfiles", "Ensures SPM and Tuist's generated lockfiles are consistent"
      def lockfiles
        Services::Lint::Lockfiles.call
      end

      desc "all", "Lint all the code in the repository"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def all
        Services::Lint::Lockfiles.call
        lint_tuist(fix: options[:fix])
        Services::Lint::Tuistbench.call(fix: options[:fix])
        Services::Lint::Fixturegen.call(fix: options[:fix])
        Services::Lint::Fourier.call(fix: options[:fix])
      end

      no_commands {
        def lint_tuist(fix: false)
          Services::Lint::Tuist.call(fix: fix)
          Services::Format::Swift.call(fix: fix)
        end
      }
    end
  end
end
