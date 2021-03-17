# frozen_string_literal: true

require "cli/ui"
require "zeitwerk"
require "thor"

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

    def self.exit_on_failure?
      true
    end
  end
end
