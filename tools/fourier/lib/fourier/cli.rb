# frozen_string_literal: true
require "thor"

module Fourier
  class CLI < Thor
    desc "test", "Run tests"
    subcommand "test", Commands::Test

    def self.exit_on_failure?
      true
    end
  end
end
