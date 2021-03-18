# frozen_string_literal: true
module Fourier
  module Commands
    class Lint < Base
      desc "swift", "Lint the Swift code of the project"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def swift
        ::CLI::UI.frame("Linting Swift code", frame_style: :bracket) do
          Services::Lint::Swift.call(fix: options[:fix])
        end
      end

      desc "ruby", "Lint the Ruby code of the project"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def ruby
        ::CLI::UI.frame("Linting Ruby code", frame_style: :bracket) do
          Services::Lint::Ruby.call(fix: options[:fix])
        end
      end

      desc "all", "Lint all the code in the repository"
      option :fix, desc: "When passed, it fixes the issues", type: :boolean, default: false
      def all
        ::CLI::UI.frame("Linting Swift code", frame_style: :bracket) do
          Services::Lint::Swift.call(fix: options[:fix])
        end
        ::CLI::UI.frame("Linting Ruby code", frame_style: :bracket) do
          Services::Lint::Ruby.call(fix: options[:fix])
        end
      end
    end
  end
end
