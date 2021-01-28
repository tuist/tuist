# frozen_string_literal: true
require "thor"

module Fourier
  class CLI < Thor
    desc "test", "Run tests"
    subcommand "test", Commands::Test

    desc "github", "Utilities to manage the repository and the organization on GitHub"
    subcommand "github", Commands::GitHub

    def self.exit_on_failure?
      true
    end
  end
end
