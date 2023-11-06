# frozen_string_literal: true

require "cli/ui"
require "thor"
require "zeitwerk"

CLI::UI::StdoutRouter.enable

loader = Zeitwerk::Loader.new
loader.push_dir(__dir__)
loader.inflector.inflect("github_client" => "GitHubClient")
loader.inflector.inflect("github" => "GitHub")
loader.setup

module Fourier
  class CLI < Thor
    class_option :verbose, type: :boolean

    desc "benchmark", "Benchmark Tuist"
    def benchmark
      Services::Benchmark.call
    end

    class << self
      def exit_on_failure?
        true
      end
    end
  end
end
