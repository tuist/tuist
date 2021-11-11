# frozen_string_literal: true

require "octokit"

module Fourier
  module Utilities
    class GitHubClient < Octokit::Client
      Error = Class.new(StandardError)
      TokenNotFound = Class.new(Error)

      def initialize(environment: ENV)
        token = environment["GITHUB_TOKEN"]
        if token.nil?
          raise TokenNotFound, "GITHUB_TOKEN is not present in the environment and therefore"\
            " an authenticated instance of GitHub client cannot be created."
        end

        super(access_token: environment.fetch("GITHUB_TOKEN"))
        self.auto_paginate = true
      end
    end
  end
end
