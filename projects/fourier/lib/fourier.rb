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

    desc "build", "Build projects"
    subcommand "build", Commands::Build

    desc "serve", "Serve projects"
    subcommand "serve", Commands::Serve

    desc "github", "Utilities to manage the repository and the organization on GitHub"
    subcommand "github", Commands::GitHub

    desc "generate", "Generate the Xcode project to work on Tuist, focusing on the target TARGET"
    subcommand "generate", Commands::Generate

    desc "edit", "Edit Tuist's project manifest in Xcode"
    subcommand "edit", Commands::Edit

    desc "lint", "Lint the project's code"
    subcommand "lint", Commands::Lint

    desc "update", "Update project's components"
    subcommand "update", Commands::Update

    desc "bundle", "Bundle tuist and tuistenv"
    subcommand "bundle", Commands::Bundle

    desc "encrypt", "Encrypt content in the repository"
    subcommand "encrypt", Commands::Encrypt

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

    desc "up", "Ensures the environment is ready to work on Tuist"
    def up
      Services::Up.call
    end

    desc "check", "Checks whether the environment is setup for working on Tuist"
    def check
      Services::Check.call
    end

    desc "release", "Prepares the Tuist binary and dependencies for release"
    subcommand "release", Commands::Release

    class << self
      def exit_on_failure?
        true
      end
    end
  end
end
