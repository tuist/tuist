# frozen_string_literal: true
require "thor"

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

    def self.exit_on_failure?
      true
    end
  end
end
