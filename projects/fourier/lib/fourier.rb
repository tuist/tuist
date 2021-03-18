# frozen_string_literal: true

require "cli/ui"
require "zeitwerk"
require "thor"

::CLI::UI::StdoutRouter.enable

loader = Zeitwerk::Loader.new
loader.push_dir(__dir__)
loader.inflector.inflect("github_client" => "GitHubClient")
loader.inflector.inflect("github" => "GitHub")
loader.setup

module Fourier
  class CLI < Thor
    desc "test", "Run tests"
    subcommand "test", Commands::Test

    desc "build", "Build targets"
    subcommand "build", Commands::Build

    desc "github", "Utilities to manage the repository and the organization on GitHub"
    subcommand "github", Commands::GitHub

    desc "generate", "Generate the Xcode project to work on Tuist"
    subcommand "generate", Commands::Generate

    desc "edit", "Edit Tuist's project manifest in Xcode"
    subcommand "edit", Commands::Edit

    desc "lint", "Lint the project's code"
    subcommand "lint", Commands::Lint

    desc "format", "Format the project's code"
    subcommand "format", Commands::Format

    desc "focus TARGET", "Edit Tuist's project focusing on the target TARGET"
    def focus(target)
      Services::Focus.call(target: target)
    end

    desc "tuist", "Runs Tuist"
    def tuist(*arguments)
      Services::Tuist.call(*arguments)
    end

    desc "fixture", "Generate a fixture"
    option(
      :path,
      desc: "The path to the directory where the fixture will be generated",
      type: :string,
      required: false,
      aliases: :p,
      default: "Fixture"
    )
    option(
      :projects,
      desc: "The number of projects to generate",
      type: :numeric,
      required: true,
      aliases: :P
    )
    option(
      :targets,
      desc: "The number of targets to generate",
      type: :numeric,
      required: true,
      aliases: :t
    )
    option(
      :sources,
      desc: "The number of sources to generate",
      type: :numeric,
      required: true,
      aliases: :s
    )
    def fixture
      path = File.expand_path(options[:path], Dir.pwd)
      Services::Fixture.call(
        path: path,
        projects: options[:projects],
        targets: options[:targets],
        sources: options[:sources]
      )
    end

    desc "benchmark", "Benchmark Tuist"
    def benchmark
      ::CLI::UI.frame("Benchmarking Tuist", frame_style: :bracket) do
        Services::Benchmark.call
      end
    end

    desc "up", "Ensures the environment is ready to work on Tuist"
    def up
      Services::Up.call
    end

    desc "check", "Checks whether the environment is setup for working on Tuist"
    def check
      Services::Check.call
    end

    def self.exit_on_failure?
      true
    end
  end
end
