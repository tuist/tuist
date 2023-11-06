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

    desc "test", "Run tests"
    subcommand "test", Commands::Test

    desc "fixture", "Generate a fixture"
    option(
      :path,
      desc: "The path to the directory where the fixture will be generated",
      type: :string,
      required: false,
      aliases: :p,
      default: "Fixture",
    )
    option(
      :projects,
      desc: "The number of projects to generate",
      type: :numeric,
      required: true,
      aliases: :P,
    )
    option(
      :targets,
      desc: "The number of targets to generate",
      type: :numeric,
      required: true,
      aliases: :t,
    )
    option(
      :sources,
      desc: "The number of sources to generate",
      type: :numeric,
      required: true,
      aliases: :s,
    )
    def fixture
      path = File.expand_path(options[:path], Dir.pwd)
      Services::Fixture.call(
        path: path,
        projects: options[:projects],
        targets: options[:targets],
        sources: options[:sources],
      )
    end

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
